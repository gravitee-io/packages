output "public_ip_address" {
  value = azurerm_linux_virtual_machine.rpm_vm.public_ip_address
}

output "ssh_command_to_connect" {
  value = "ssh -i ${module.dependencies.local_sensitive_file-ssh_private_key-filename} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \\\n\t -L 18082:localhost:18082 -L 8082:localhost:8082 -L 8083:localhost:8083 -L 8084:localhost:8084 -L 8085:localhost:8085 \\\n\t ${var.username}@${azurerm_linux_virtual_machine.rpm_vm.public_ip_address}"
}

output "scp_command_to_push_rpm" {
  value = "scp -i ${module.dependencies.local_sensitive_file-ssh_private_key-filename} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \\\n\t ../../../apim/4.x/graviteeio-apim-*-4x*.rpm ${var.username}@${azurerm_linux_virtual_machine.rpm_vm.public_ip_address}:."
}
