# Copyright (c) 2022, Intrepid Control Systems, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Set up builtin args
# They're in the back so user can use front if needed
set num_builtin_args 9
set builtin_args_start_idx [expr $argc - $num_builtin_args]
set unused_idx [expr $builtin_args_start_idx + 0]
set stats_idx [expr $builtin_args_start_idx + 1]
set threads_idx [expr $builtin_args_start_idx + 2]
set bd_only_idx [expr $builtin_args_start_idx + 3]
set synth_only_idx [expr $builtin_args_start_idx + 4]
set impl_only_idx [expr $builtin_args_start_idx + 5]
set force_idx [expr $builtin_args_start_idx + 6]
set use_vitis_idx [expr $builtin_args_start_idx + 7]
set usr_access_idx [expr $builtin_args_start_idx + 8]

set stats_file [lindex $argv $stats_idx]
set max_threads [lindex $argv $threads_idx]
set bd_only [lindex $argv $bd_only_idx]
set synth_only [lindex $argv $synth_only_idx]
set impl_only [lindex $argv $impl_only_idx]
set force [lindex $argv $force_idx]
set use_vitis [lindex $argv $use_vitis_idx]
set usr_access [lindex $argv $usr_access_idx]


puts "stats_file: $stats_file"
puts "max_threads: $max_threads"

# Stats tracking variables
set synth_time 0
set total_start 0
set impl_time 0
set report_time 0
set export_time 0
set global_start 0
set bitstream_time 0
set setup_start [clock seconds]
set setup_time 0

# Build tracking variables
set worst_slack 0
set lut_util 0
set ram_util 0
set total_power 0

proc build {proj_name top_name proj_dir {allow_timing_fail 0}} {
  global synth_time
  global total_start
  global impl_time
  global report_time
  global export_time
  global total_start
  global setup_start
  global setup_time
  global bitstream_time
  global stats_file
  global max_threads
  global usr_access
  global power_threshold

  set output_dir [file normalize $proj_dir/../output]

  configure_warnings_and_errors

  # If anything happened before now, that was setup (BD generation etc)
  set setup_time [expr [clock seconds] - $setup_start]
  puts "Building!"
  set_param general.maxThreads $max_threads
  if {$total_start == 0} {
    # Some other methods of running this start the clock earlier
    # Do it here if no one else did
    set total_start [clock seconds]
    set setup_time 0
  }

  # Synth
  set start [clock seconds]
  launch_runs -jobs $max_threads -verbose synth_1
  wait_on_run synth_1
  if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    set failed_runs [get_runs -filter {IS_SYNTHESIS && PROGRESS < 100}]
    set runs_dir ${proj_dir}/${proj_name}.runs/
    foreach run $failed_runs {
      set log_dir ${runs_dir}/${run}
      set log ${log_dir}/runme.log
      if {[file exists $log]} {
        puts "========== START LOG FOR ${run} =========="
        puts [read [open ${log} r]]
        puts "========== END LOG FOR ${run} =========="
      } else {
        puts "NO LOG FOR ${run}"
      }
    }

    error "ERROR: Synthesis failed"
    exit 1
  }
  set synth_time [expr [clock seconds] - $start]

  exit_if_synth_only
  
  # Impl
  set start [clock seconds]
  launch_runs -jobs $max_threads -verbose impl_1
  wait_on_run impl_1
  if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: Implementation failed"
    exit 1
  }
  set impl_time [expr [clock seconds] - $start]
  
  # Report
  set start [clock seconds]
  open_run impl_1
  set timing_rpt [file normalize "$stats_file/../timing.rpt"]
  report_timing_summary -delay_type min_max -report_unconstrained -max_paths 10 -input_pins -file $timing_rpt
  global worst_slack
  set worst_slack [get_property SLACK [get_timing_paths -delay_type min_max -nworst 1]]
  set timing_pass [expr {$worst_slack >= 0}]
  if {$timing_pass == 0} {
    puts "ERROR: Failed to meet timing! Worst path slack was $worst_slack"
    if {$allow_timing_fail == 0}
    {
      exit 1
    } else {
      puts "CRITICAL WARNING: Requested to continue on timing failure, continuing anyways.  USE WITH CAUTION"
    }
  } else {
    puts "Timing met with $worst_slack ns of slack"
  }
  # Utilization
  set util_rpt [file normalize "$stats_file/../utilization.rpt"]
  report_utilization -file $util_rpt
  set lut_line [lindex [grep "CLB LUTs" $util_rpt] 0]
  set lut_line_split [split $lut_line "|"]
  global lut_util
  set lut_util [string trim [lindex $lut_line_split 5]]
  if { $lut_util >= 80} {
    puts "CRITICAL WARNING: Part is nearly full ($lut_util %), expect timing problems if anything changed!!"
  } else {
    puts "LUT utilization is $lut_util %"
  }
  set util_hier_rpt [file normalize "$stats_file/../utilization_hierarchical.rpt"]
  report_utilization -hierarchical -file $util_hier_rpt
  set ram_line [lindex [grep "Block RAM Tile" $util_rpt] 0]
  set ram_line_split [split $ram_line "|"]
  global ram_util
  set ram_util [string trim [lindex $ram_line_split 5]]
  if { $ram_util >= 85} {
    puts "CRITICAL WARNING: Part RAM is nearly full ($lut_util %), expect issues inserting ILA!!"
  } else {
    puts "RAM utilization is $ram_util %"
  }
  # Power
  set power_rpt [file normalize "$stats_file/../power.rpt"]
  report_power -file $power_rpt
  set power_line [lindex [grep "Total On-Chip Power (W)" $power_rpt] 0]
  set power_line_split [split $power_line "|"]
  global total_power
  set total_power [string trim [lindex $power_line_split 2]]
  if { $power_threshold && $total_power > $power_threshold} {
    puts "ERROR: Total power ($total_power W) exceeds threshold ($power_threshold W)!"
    exit 1
  } else {
    puts "Total power is $total_power W"
  }

  # Set access bits 
  set_property BITSTREAM.CONFIG.USR_ACCESS $usr_access [current_design]
  set_property BITSTREAM.CONFIG.USERID     $usr_access [current_design]

  set report_time [expr [clock seconds] - $start]
  
  exit_if_impl_only
  # Bitstream
  set start [clock seconds]

  launch_runs impl_1 -to_step write_bitstream -jobs $max_threads
  wait_on_run impl_1
  set bitstream_time [expr [clock seconds] - $start]
  
  # Export
  puts "Exporting files..."
  set start [clock seconds]
  
  set bitstream ${proj_dir}/${proj_name}.runs/impl_1/${top_name}.bit
  global use_vitis
  if {[file exists $bitstream]} {
    if { $use_vitis == 1 } {
      set xsa $output_dir/${top_name}.xsa
      write_hw_platform -fixed -include_bit -force -file $xsa
    } else {
    file copy -force $bitstream $output_dir/
    set hwdef ${proj_dir}/${proj_name}.runs/impl_1/${top_name}.hwdef

    if {[file exists $hwdef]} {
      write_hwdef -force -file $hwdef
      
      set sysdef ${proj_dir}/${proj_name}.runs/impl_1/${top_name}.sysdef
      write_sysdef -force -hwdef ${hwdef} -bitfile ${bitstream} -file ${sysdef}

      set hdf $output_dir/system.hdf
      file copy -force ${sysdef} ${hdf}
    } else {
      puts "ERROR: No HDF found! Should be $hwdef"
      exit 1
    }
    }

  } else {
    puts "ERROR: No bitstream found! Should be $bitstream"
    exit 1
  }

  set proj_ltx ${proj_dir}/${proj_name}.runs/impl_1/${top_name}.ltx
  set ltx $output_dir/design_1_wrapper.ltx
  if {[file exists $proj_ltx]} {
    file copy -force ${proj_ltx} ${ltx}
  }
  set export_time [expr [clock seconds] - $start]
  
  report_stats

  close_project
}

proc report_stats {} {
  global setup_time
  global synth_time
  global total_start
  global impl_time
  global report_time
  global export_time
  global total_start
  global stats_file
  global bitstream_time
  # Build stats
  global worst_slack
  global lut_util
  global ram_util
  global total_power
  set total_time [expr [clock seconds] - $total_start]
  
  set stats_chan [open $stats_file "w+"]
  puts $stats_chan "# Time stats"
  puts $stats_chan "setup_time:     $setup_time sec"
  puts $stats_chan "synth_time:     $synth_time sec"
  puts $stats_chan "impl_time:      $impl_time sec"
  puts $stats_chan "report_time:    $report_time sec"
  puts $stats_chan "bitstream_time: $bitstream_time sec"
  puts $stats_chan "export_time:    $export_time sec"
  puts $stats_chan "total_time:     $total_time sec"
  puts $stats_chan "# Build stats"
  puts $stats_chan "worst_slack:    $worst_slack ns"
  puts $stats_chan "lut_util:       ${lut_util}%"
  puts $stats_chan "ram_util:       ${ram_util}%"
  puts $stats_chan "total_power:    $total_power W"
  close $stats_chan
}

proc build_device {proj_name top proj_dir bd_files make_wrapper {allow_timing_fail 0}} {
  source_bd_files $bd_files $top $make_wrapper
  build $proj_name $top $proj_dir $allow_timing_fail
}

proc source_bd_files {bd_files top make_wrapper} {
  # #############################################################################
  # Block design files
  # #############################################################################

  # Create block design

  foreach {bd_file} $bd_files {
    puts "File is $bd_file"
    set ret [source $bd_file]
    if {${ret} != "" } {
      exit ${ret}
    }

  }

  # Generate the wrapper
  if {$make_wrapper == 1} {
    make_wrapper -files [get_files $top.bd] -top -import
  }

  set_property "top" $top [get_filesets sources_1]

  # Update the compile order
  update_compile_order -fileset sources_1
  update_compile_order -fileset sim_1
  exit_if_bd_only

}

proc build_block { filelist build_dir device generics {board 0} {bd_file 0} {top 0} {ip_repo 0}} {
  set proj_name "proj"
  # User must call their top level wrapper entity top
  if {$top != 0} {
    set top_name $top
  } else {
    set top_name "top"
  }
  set part $device
  set proj_dir $build_dir/$proj_name
  clean_proj_if_needed $proj_dir
  
  puts "Running vivado out of [pwd]"
  
  # Make clean
  if {[file exists $proj_dir]} {
    file delete -force $proj_dir
  }
  create_project -force $proj_name $proj_dir -part $part

  if {$board != 0} {
    set_property BOARD_PART $board [current_project]
  }

  if {$ip_repo != 0} {
    set_ip_repos $ip_repo
  }

  if {$bd_file != 0} {
    source_bd_files [list $bd_file] $top_name 1
  }

  configure_warnings_and_errors
  
  # Add files
  add_files_from_filelist $filelist

  # Settings
  set_property target_language VHDL [current_project]
  set_property top $top_name [current_fileset]
  set_property "xpm_libraries" "XPM_CDC XPM_FIFO XPM_MEMORY" [current_project]
  set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
  set_property STEPS.OPT_DESIGN.IS_ENABLED false [get_runs impl_1]

  # Set generics
  dict for {k v} $generics {
    puts "Setting top level param $k to $v"
    set_property generic $k=$v [current_fileset]
  }

  build $proj_name $top_name $proj_dir
}

proc clean_proj_if_needed {proj_dir} {
  global argv
  global total_start
  global setup_start
  if {[file exists $proj_dir]} {
    global force
    if {$force == 0} {
      puts "ERROR: Project dir $proj_dir already exists, provide -f/--force to force delete"
      exit 1
    }
  }
  set total_start [clock seconds]
  set setup_start [clock seconds]
  file delete -force $proj_dir
}

proc exit_if_bd_only {} {
  global bd_only
  global setup_time
  global setup_start
  if {$bd_only == 1} {
    set setup_time [expr [clock seconds] - $setup_start]
    report_stats
    exit 0
  }
}

proc exit_if_impl_only {} {
  global impl_only
  if {$impl_only == 1} {
    report_stats
    exit 0
  }
}

proc exit_if_synth_only {} {
  global synth_only
  if {$synth_only == 1} {
    report_stats
    exit 0
  }
}

proc add_files_from_filelist {filelist} {
  puts "Adding files from ${filelist}"
  source $filelist
  foreach {path lib standard} $all_sources {
    add_files $path
    set file_obj [get_files -of_objects [get_filesets sources_1] [list "*$path"]]
    if {[string compare $standard "N/A"] != 0} {
      set_property -name "file_type" -value $standard -objects $file_obj
    }
    if {[string compare $lib "N/A"] != 0} {
      set_property -name "library" -value $lib -objects $file_obj
    }
  }
  puts "Added files!"
}

proc dict_get_default {dict param default} {
  if { [dict exists $dict $param] } {
    set value [dict get $dict $param]
  } else {
    # Default on
    set value $default
  }
  return $value
}

proc set_ip_repos {repos} {
  # #############################################################################
  # IP files
  # #############################################################################
  # Set IP repository paths
  set repos_string [join $repos " "]
  puts "repos_string is $repos_string"
  set_property "ip_repo_paths" "$repos_string" [current_fileset]

  # Rebuild user ip_repo's index before adding any source files
  update_ip_catalog -rebuild
}

proc build_device_from_params {params} {
  global power_threshold

  # Grab things from the dict
  set proj_name [dict get $params proj_name ]
  set vivado_year [dict get $params vivado_year ]
  set part [dict get $params part ]
  set top [dict get $params top ]
  if {[dict exists $params ip_repos]} {
    set ip_repos [dict get $params ip_repos ]
  } elseif {[dict exists $params ip_repo]} {
    set ip_repos [ list \
      [dict get $params ip_repo ] \
    ]
  }
  set hdl_files [dict_get_default $params hdl_files ""]
  set constraints_files [dict_get_default $params constraints_files ""]
  if {[dict exists $params bd_files]} {
    set bd_files [dict get $params bd_files ]
  } elseif {[dict exists $params bd_file]} {
    set bd_files [ list \
      [dict get $params bd_file ] \
    ]
  }
  set synth_strategy [dict get $params synth_strategy ]
  set impl_strategy [dict get $params impl_strategy ]
  set origin_dir [dict get $params origin_dir]
  set use_power_opt [dict_get_default $params use_power_opt 1]
  set use_post_route_phys_opt [dict_get_default $params use_post_route_phys_opt 1]
  set make_wrapper [dict_get_default $params make_wrapper 0]
  set target_language [dict_get_default $params target_language VHDL]
  set power_threshold [dict_get_default $params power_threshold 0]
  set allow_timing_fail [dict_get_default $params allow_timing_fail 0]  

  # #############################################################################

  set proj_dir [pwd]/$proj_name
  clean_proj_if_needed $proj_dir

  # Create project
  create_project $proj_name $proj_dir

  configure_warnings_and_errors

  # Set the directory path for the new project
  set proj_dir [get_property directory [current_project]]

  # Set project properties
  set obj [get_projects $proj_name]
  set_property "default_lib" "xil_defaultlib" $obj
  set_property -name "ip_cache_permissions" -value "read write" -objects $obj
  set_property -name "ip_output_repo" -value "$proj_dir/$proj_name.cache/ip" -objects $obj
  set_property "part" "$part" $obj
  set_property "sim.ip.auto_export_scripts" "1" $obj
  set_property -name "ip_interface_inference_priority" -value "" -objects $obj
  set_property "simulator_language" "Mixed" $obj
  set_property "target_language" "$target_language" $obj
  set_property -name "enable_vhdl_2008" -value "1" -objects $obj
  set_property -name "xpm_libraries" -value "XPM_CDC XPM_FIFO XPM_MEMORY" -objects $obj

  # #############################################################################
  # HDL files
  # #############################################################################

  # Create 'sources_1' fileset (if not found)
  if {[string equal [get_filesets -quiet sources_1] ""]} {
    create_fileset -srcset sources_1
  }

  if { $hdl_files != ""} {
  add_files -norecurse -fileset [get_filesets sources_1] $hdl_files
  } else {
    puts "WARNING: No hdl files specified, assuming all are in IP cores"
  }

  set filelist [pwd]/filelist.tcl
  if { [file exists $filelist] } {
    add_files_from_filelist $filelist
  } else {
    puts "No filelist provided"
  }

  set_ip_repos $ip_repos

  #upgrade_ip [get_ips]

  # #############################################################################
  # Constraints files
  # #############################################################################

  # Create 'constrs_1' fileset (if not found)
  if {[string equal [get_filesets -quiet constrs_1] ""]} {
    create_fileset -constrset constrs_1
  }

  if { $constraints_files != ""} {
  add_files -norecurse -fileset [get_filesets constrs_1] $constraints_files
  } else {
    puts "CRITICAL WARNING: No constraints specified, if this isn't a test project, you need constraints!"
  }

  # Create 'sim_1' fileset (if not found)
  if {[string equal [get_filesets -quiet sim_1] ""]} {
    create_fileset -simset sim_1
  }

  # #############################################################################
  # Simulation settings
  # #############################################################################

  # Set 'sim_1' fileset object
  set obj [get_filesets sim_1]
  # Empty (no sources present)

  # Set 'sim_1' fileset properties
  set obj [get_filesets sim_1]
  set_property "top" $top $obj
  set_property "xelab.nosort" "1" $obj
  set_property "xelab.unifast" "" $obj

  # #############################################################################
  # Synthesis and implementation
  # #############################################################################
  # Create 'synth_1' run (if not found)
  if {[string equal [get_runs -quiet synth_1] ""]} {
    create_run -name synth_1 -part $part -flow {Vivado Synthesis $vivado_year} -strategy $synth_strategy -constrset constrs_1
  } else {
    set_property strategy $synth_strategy [get_runs synth_1]
    set_property flow "Vivado Synthesis $vivado_year" [get_runs synth_1]
  }
  set obj [get_runs synth_1]
  set_property "needs_refresh" "1" $obj
  set_property "part" "$part" $obj

  # set the current synth run
  current_run -synthesis [get_runs synth_1]

  # Create 'impl_1' run (if not found)
  if {[string equal [get_runs -quiet impl_1] ""]} {
    create_run -name impl_1 -part $part -flow {Vivado Implementation $vivado_year} -strategy $impl_strategy -constrset constrs_1 -parent_run synth_1
  } else {
    set_property strategy $impl_strategy [get_runs impl_1]
    set_property flow "Vivado Implementation $vivado_year" [get_runs impl_1]
  }
  set obj [get_runs impl_1]
  set_property "needs_refresh" "1" $obj
  set_property "part" "$part" $obj
  set_property -name "steps.power_opt_design.is_enabled" -value "$use_power_opt" -objects $obj
  set_property -name "steps.post_place_power_opt_design.is_enabled" -value "$use_power_opt" -objects $obj
  set_property -name "steps.post_route_phys_opt_design.is_enabled" -value "$use_post_route_phys_opt" -objects $obj
  set_property -name "steps.post_route_phys_opt_design.args.directive" -value "AggressiveExplore" -objects $obj
  set_property "steps.write_bitstream.args.readback_file" "0" $obj
  set_property "steps.write_bitstream.args.verbose" "0" $obj

  # set the current impl run
  current_run -implementation [get_runs impl_1]

  build_device $proj_name $top $proj_dir $bd_files $make_wrapper $allow_timing_fail
}

proc grep { {a} {fs {*}} } {
  set o [list]
  foreach n [lsort -incr -dict [glob $fs]] {
    set f [open $n r]
    set c 0
    set new 1
    while {[eof $f] == 0} {
        set l [gets $f]
        incr c
        if {[string first $a $l] > -1} {
          lappend o "$l"
          # if {$new == 1} {set new 0; append o "*** $n:" \n}
          # append o "$c:$l" \n
        }
    }
    close $f
  }
  return $o
}

proc get_ip_repo_paths {origin_dir ip_repo part} {
  set ip_dirs [glob -type d -dir "[file normalize $origin_dir/$ip_repo]" "*"]
  set ip_repo_paths [list]
  foreach ip_dir $ip_dirs {
    # First, check if there is a part specific component
    # This requires a standard directory structure
    set is_zynq [string match "xc7z*" $part]
    set is_uplus [string match "xczu*" $part]
    if {$is_zynq == 0 && $is_uplus == 0} {
      puts "ERROR: Unknown part type for $part.  Probably need to update pattern match"
      report_stats
      exit 1
    }
    if {$is_zynq == 1} {
      set part_ip_dir "${ip_dir}/zynq"
    } else {
      set part_ip_dir "${ip_dir}/zynquplus"
    }
    set part_component "${part_ip_dir}/component.xml"
    if { [file exists $part_component] } {
      puts "Adding IP $part_ip_dir"
      lappend ip_repo_paths $part_ip_dir
    } else {
      # Didn't find a part specific IP
      # Ideally component is at root, but some old IP has it in random places
      # Just add the directory, it's in there somewhere
      puts "Adding IP $ip_dir"
      lappend ip_repo_paths $ip_dir
    }
  }
  return $ip_repo_paths
}

proc configure_warnings_and_errors {} {
  puts "INFO: Setting severities"
  # Force error if parameter name not found on IP core.  Found on IP upgrade with generic name changes
  set_msg_config -id {BD 41-1276} -new_severity {ERROR}
  # Reclassify assertion warnings to info messages.  These are from the Xilinx IP, and assertions are not used
  set_msg_config -id {[Synth 8-312]} -new_severity INFO

  # Reclassify 8-3332 as an info message.  These are primarily created by the synthesis tool
  set_msg_config -id {[Synth 8-3332]} -new_severity INFO
}
