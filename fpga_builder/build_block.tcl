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

# Parse args
set this_dir [ file dirname [ file normalize [ info script ] ] ]
set filelist [lindex $argv 0]
set build_dir [lindex $argv 1]
set device [lindex $argv 2]
set board [lindex $argv 3]
set bd_file [lindex $argv 4]
set top [lindex $argv 5]
set ip_repo [lindex $argv 6]
set num_generics [lindex $argv 7]
set generic_base_idx 8
# Set up generics dict
set generics [dict create]
for {set i 0} {$i < $num_generics*2} {incr i 2} {
    set key_idx [expr $generic_base_idx + $i]
    set value_idx [expr $key_idx + 1]
    set k [lindex $argv $key_idx]
    set v [lindex $argv $value_idx]
    dict set generics $k $v
}
puts $generics
# Build the thing
source $this_dir/utils.tcl
build_block $filelist $build_dir $device $generics $board $bd_file $top $ip_repo
