#!/bin/bash
# Meant to be used with Telegraf; metrics are produced in logfmt format
#   https://brandur.org/logfmt
#   https://github.com/influxdata/telegraf/tree/master/plugins/parsers/logfmt

VERSION="0.0.1"

### Environment
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

### Functions
##  Generic
function log_err() {
    echo "$@" 1>&2
}

get_version() {
    echo $VERSION
}

get_network() {
    function get_bits_per_second() {
        # Trim whitespaces from xargs
        iface="$(echo -e "${1}" | tr -d '[:space:]')"
        tx_b=`cat /sys/class/net/$iface/statistics/tx_bytes`
        rx_b=`cat /sys/class/net/$iface/statistics/rx_bytes`
        sleep 1
        tx_a=`cat /sys/class/net/$iface/statistics/tx_bytes`
        rx_a=`cat /sys/class/net/$iface/statistics/rx_bytes`
        # echo "$iface""_tx=`echo "($tx_a-$tx_b)*8" | bc`"
        # echo "$iface""_rx=`echo "($rx_a-$rx_b)*8" | bc`"
        echo "$iface""_tx=$(python -c "print ($tx_a-$tx_b)*8")"
        echo "$iface""_rx=$(python -c "print ($rx_a-$rx_b)*8")"
    }

    function get_link_state() {
        iface="$(echo -e "${1}" | tr -d '[:space:]')"
        val=`cat /sys/class/net/$iface/carrier`
        if [ -z "$val" ]; then val=0; fi
        echo "$iface""_link=$val"
    }

    function get_link_speed() {
        iface="$(echo -e "${1}" | tr -d '[:space:]')"
        val=`cat /sys/class/net/$iface/speed`
        # When the link is down, speed seems to have some garbage value, in such cases set 0 instead
        if [ -z "$val" ] || [ "$val" -gt "200000" ] || [ "$val" -lt "0" ]; then val=0; fi
        echo "$iface""_speed=$val"
    }

    function get_for_all_active_interfaces() {
        type nmcli 2>/dev/null
        if [ $? -eq 0 ]; then
            list=`nmcli device status | awk '$3 == "connected" {print $1}'`
        else
            list=`find /sys/class/net/ -type l -printf "%f\r\n"`
        fi
        total=`echo -e "$list" | wc -l`
        export -f get_bits_per_second get_link_state get_link_speed
        # To get more accurate data, fetch in parallel
        echo -e "$list" | xargs -L 1 -n 1 -P $total bash -c 'get_bits_per_second "$@" 2>/dev/null' _
        echo -e "$list" | xargs -L 1 -n 1 -P $total bash -c 'get_link_state "$@" 2>/dev/null' _
        echo -e "$list" | xargs -L 1 -n 1 -P $total bash -c 'get_link_speed "$@" 2>/dev/null' _
    }

    get_for_all_active_interfaces | tr '\n' ' ' ; echo
}

##  Process input
begin() {
    case "$CAT" in
        net)
            get_network
            ;;
        *)
            log_err "Unsupported category"
    esac
}

# Help
get_help() {
    script_name=`basename "$0"`
    echo -e "./$script_name [option]\n"
    echo "Options:"
    echo -e "\t-h|--help\tShow this message and exist"
    echo -e "\t-c <category>\tThe category for which to produce output"
    echo ""
    echo -e "Categories:"
    echo -e "\tnet        Returns network interface metrics"
    echo ""
    echo "Examples:"
    echo -e "\t./$script_name -c net"
}

# Read input
while getopts :c: option
do
     case "${option}"
     in
        c) CAT=${OPTARG};;
     esac
done

# Main
case "$1" in
    -h|--help)
        get_help
        ;;
    -v|--version)
        get_version
        ;;
    *)
        if [ -z "$CAT" ]; then
            log_err "No category was provided"
        else
            begin
        fi
esac
