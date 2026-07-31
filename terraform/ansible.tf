resource "local_file" "ansible_inventory" {

  filename = "../ansible/inventory.ini"

  content = templatefile("${path.module}/inventory.tpl", {

    master_ip = aws_eip.master.public_ip

    worker_ips = aws_instance.k8s_worker[*].public_ip

  })
}
