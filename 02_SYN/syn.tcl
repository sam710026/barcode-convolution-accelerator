# Setting environment
sh mkdir -p Netlist
sh mkdir -p Report

set company {NTUGIEE}
set designer {Student}



set hw3_dc_lib_dir /share1/tech/CBDK_IC_Contest_v2.5/SynopsysDC/db
if {[info exists ::env(HW3_DC_LIB_DIR)]} {
    set hw3_dc_lib_dir $::env(HW3_DC_LIB_DIR)
}
set search_path [concat [list $hw3_dc_lib_dir ../sram_256x8 ../sram_512x8 ../sram_4096x8 ../ ./] $search_path]
set target_library   "slow.db                 \
                      sram_256x8_slow_syn.db  \
                      sram_512x8_slow_syn.db  \
                      sram_4096x8_slow_syn.db \
                     "
set link_library     "* $target_library dw_foundation.sldb"
set symbol_library   "tsmc13.sdb generic.sdb"
set synthetic_library "dw_foundation.sldb"
set default_schematic_options {-size infinite}


# Import Design
set DESIGN "core"

set hdlin_translate_off_skip_text "TRUE"
set edifout_netlist_only "TRUE"
set verilogout_no_tri true

set hdlin_enable_presto_for_vhdl "TRUE"
set sh_enable_line_editing true
set sh_line_editing_mode emacs
history keep 100
alias h history

# Time the reset tree's recovery/removal as normal paths.
set enable_recovery_removal_arcs true
analyze -format sverilog "flist.sv"
elaborate $DESIGN
current_design [get_designs $DESIGN]
link

source -echo -verbose ./core_dc.sdc

# Compile Design
current_design [get_designs ${DESIGN}]

check_design > Report/check_design.txt
check_timing > Report/check_timing.txt
#set high_fanout_net_threshold 0

# ---- HW3 optimization options (compile options only; SDC unchanged) ----
# Knobs: env HW3_RETIME / HW3_RT_MARGIN / HW3_DP_AREA / HW3_AREA_OPT override defaults.
foreach {hw3_k hw3_d} {HW3_RETIME 0 HW3_RT_MARGIN 0 HW3_DP_AREA 0 HW3_AREA_OPT 1 HW3_FA_DT 1} {
    if {[info exists ::env($hw3_k)]} {set $hw3_k $::env($hw3_k)} elseif {![info exists $hw3_k]} {set $hw3_k $hw3_d}
    echo "HW3_KNOB $hw3_k = [set $hw3_k]"
}

# csa_fa wrappers: flatten into their parent so ADDFX1 leaf cells sit directly in
# hw3_fused_heap (retiming cannot cross hierarchy; avoids 1788 uniquified designs).
# uniquify first: the 4 heap instances share one design, so their children
# cannot be ungrouped until each heap is unique.
uniquify
set hw3_fa [get_cells -quiet -hierarchical -filter "ref_name =~ csa_fa*"]
echo "HW3_CSA_FA_INSTANCES [sizeof_collection $hw3_fa]"
if {[sizeof_collection $hw3_fa] > 0} { ungroup $hw3_fa -flatten }

# Fast raw-capture flops instantiated in RTL (cap_ff8 -> DFFHQX8): keep them from
# being down-sized by area recovery (TA Q42-B: instantiation + dont_touch allowed).
set hw3_cap [get_cells -quiet -hierarchical -filter "ref_name == DFFHQX8"]
echo "HW3_CAP_DFFHQX8 [sizeof_collection $hw3_cap]"
if {[sizeof_collection $hw3_cap] > 0} { set_dont_touch $hw3_cap true }
# Optional (friend's flow): protect the instantiated heap ADDFX1 cells. Default on.
if {$HW3_FA_DT} {
    set hw3_fa_cells [get_cells -quiet -hierarchical -filter "ref_name == ADDFX1"]
    echo "HW3_FA_DONT_TOUCH [sizeof_collection $hw3_fa_cells]"
    set_size_only $hw3_fa_cells true
}

uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

# Area recovery after timing is met.
set_max_area 0

# Datapath generator goal: 1 = build adder trees / final adders (DesignWare) for area.
if {$HW3_DP_AREA} {
    if {[catch {set_dp_smartgen_options -optimize_for area} hw3_msg]} {
        echo "HW3: set_dp_smartgen_options not applied: $hw3_msg"
    }
}

# Register retiming: 2 = retime the reset-free heap pipeline + compile_ultra -retime,
# 1 = compile_ultra -retime only, 0 = plain compile_ultra.
if {$HW3_RETIME >= 2} {
    set hw3_rt [get_designs -quiet hw3_fused_heap*]
    echo "HW3_RETIME_DESIGNS [get_object_name $hw3_rt]"
    if {$HW3_RT_MARGIN > 0} {
        set_optimize_registers true -design $hw3_rt -delay_threshold [expr {$cycle - $HW3_RT_MARGIN}]
    } else {
        set_optimize_registers true -design $hw3_rt
    }
}
if {$HW3_RETIME >= 1} {
    compile_ultra -retime
} else {
    compile_ultra
}

# Final area recovery: 1 = optimize_netlist -area (never degrades timing).
# Level 2 of the photo was cut off; not guessed.
if {$HW3_AREA_OPT >= 1} {
    optimize_netlist -area
}
echo "HW3_ADDF_CELLS [sizeof_collection [get_cells -quiet -hierarchical -filter {ref_name =~ ADDF*}]]"
check_design > Report/check_design_post.txt
check_timing > Report/check_timing_post.txt
report_timing -delay_type max -max_paths 20 > Report/core_setup_paths.txt
report_timing -delay_type min -max_paths 20 > Report/core_hold_paths.txt
report_constraint -all_violators > Report/core_violators.txt

# Report Output
current_design [get_designs ${DESIGN}]
report_timing -max_paths 5 > "./Report/${DESIGN}_syn.timing"
report_area -hierarchy > "./Report/${DESIGN}_syn.area"

# Output Design
current_design [get_designs ${DESIGN}]

set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true
change_names -hierarchy -rule verilog
define_name_rules name_rule -allowed {a-z A-Z 0-9 _} -max_length 255 -type cell
define_name_rules name_rule -allowed {a-z A-Z 0-9 _[]} -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
define_name_rules name_rule -case_insensitive
change_names -hierarchy -rules name_rule

remove_unconnected_ports -blast_buses [get_cells -hierarchical *]
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
set verilogout_higher_designs_first true
write -format ddc     -hierarchy -output "./Netlist/${DESIGN}_syn.ddc"
write -format verilog -hierarchy -output "./Netlist/${DESIGN}_syn.v"
write_sdf -version 2.1  -context verilog -load_delay cell ./Netlist/${DESIGN}_syn.sdf
write_sdc  ./Netlist/${DESIGN}_syn.sdc -version 1.8


report_timing
report_area -hierarchy
check_design > Report/check_design_final.txt
check_design
exit
