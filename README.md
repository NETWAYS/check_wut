check_wut
=========
 
This plugin checks the status of a WuT WebIO Klima Appliance using SNMP

It doesn't require the MIB (the OID is hardcoded into the script)

If you have multiple sensors you can specify the warning, critical
and unit options as a comma-separated list.


### Requirements

* Perl libraries: `Net::SNMP`

    
### Usage

    check_wut_health [options] <hostname> <SNMP community>

    --warning
        warning levels (comma separated) - default 20

    --critical
        critical levels (comma separated) - default 40

    --unit
        sensor measuring units (comma separated) - default C

    --timeout
        how long to wait for the reply (default 30s)

    --type
        device type (as a number). Default is 0 (autodetect)
