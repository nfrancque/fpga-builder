set ws [lindex $argv 0]
set bsp_libs [lindex $argv 1]
set xsa [lindex $argv 2]

# set the workspace
puts "Setting Vitis workspace to $ws"
setws $ws

# set the repo for the custom bsp libraries
puts "Adding repository $bsp_libs"
repo -set $bsp_libs
repo -scan

# get the first platform and activate
set pf_names [dict keys [platform list -dict]]
puts "INFO: Found the following platform projects: $pf_names."
set pf [lindex $pf_names 0]
platform active $pf

# get all apps
set app_names [dict keys [app list -dict]]
puts "INFO: Found the following app projects: $app_names."

# get all domains in the platform
set domain_names [dict keys [domain list -dict]]
puts "INFO: Found the following domains: $domain_names."

# update hardware specification file
puts "Updating hw plaform $xsa"
platform config -updatehw $xsa

# regenerate BSP source files
set success 0
set num_tries 5
while { $success == 0 } {
    puts "Regenerating BSP source files"
    if { [ catch {
        foreach d $domain_names {
            puts "Regenerating $d"
            domain active $d
            bsp regenerate
        }
        set success 1
    } err ] } {
        # Grrrr windows resource owner problems
        # Try it a couple times
        if { $num_tries == 0} {
            puts "Tried a few times but something's goofy, dying"
            exit 1
        }
        incr num_tries -1
        puts "Something happened, let's try that again"
        puts "Tries remaining: $num_tries"
    }
}

puts "Done!"
