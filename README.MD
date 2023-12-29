# Nagios Probe - CPU Load Monitoring

This Nagios probe allows you to monitor the CPU load of a system and raise alerts based on predefined thresholds.

## Prerequisites

- [Nagios](https://www.nagios.org/) must be installed on the system.
- The `iostat` program must be installed and accessible.

## Installation

1. Copy the `cpu_load.sh` script to the system where Nagios is installed.

2. Ensure that the script is executable:

   ```bash
   chmod +x cpu_load.sh
   ```

## Usage

### Options

    -h, --help: Display this help message.
    -f, --data-file: Specify the data file path (default: /var/tmp/cpu_load_data).
    -t, --thresholds: Set thresholds in the format 1:warn,crit-5:warn,crit-15:warn,crit. Example: -t 1:70,90-5:60,80-15:50,70.

### Example

To run the script with custom thresholds:

```bash
    ./cpu_load.sh -t 1:70,90-5:60,80-15:50,70
```

### Operation

    - 0 (OK): Everything is normal; CPU load is below thresholds.
    - 1 (WARNING): CPU load exceeds the warning threshold.
    - 2 (CRITICAL): CPU load exceeds the critical threshold.
    - 3 (UNKNOWN): Unexpected error or unavailability of iostat.

## Nagios Configuration Example

Here is an example Nagios configuration to monitor CPU load using this probe. Make sure to adjust the script path and thresholds according to your needs.

```bash
define command {
    command_name    cpu_load
    command_line    /path/to/cpu_load.sh -t 1:70,90-5:60,80-15:50,70
}

define service {
    use                 generic-service
    host_name           your_host
    service_description CPU Load
    check_command       cpu_load
}
```
Replace /path/to/cpu_load.sh with the absolute path to the script on your system and configure the thresholds as needed.
