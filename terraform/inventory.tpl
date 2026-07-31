
[master]
k8s-master ansible_host=${master_ip}

[workers]
%{ for idx, ip in worker_ips ~}
k8s-worker-${idx + 1} ansible_host=${ip}
%{ endfor ~}

[monitoring]
k8s-worker-3 ansible_host=${worker_ips[2]}

[logging]
k8s-worker-4 ansible_host=${worker_ips[3]}

[all:vars]
ansible_python_interpreter=/usr/bin/python3
