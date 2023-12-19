#!/bin/bash
for ((i = 0 ; i < 100000 ; i++)); do
	nvidia-smi --query-gpu=timestamp,name,pci.bus_id,driver_version,pstate,pcie.link.gen.max,pcie.link.gen.current,temperature.gpu,utilization.gpu,utilization.memory,memory.total,memory.free,memory.used --format=csv -l 10
	sleep 10
done