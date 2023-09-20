output "crack" {
   description = "Ec2"
   value = try(aws_instance.firewall)
}
output "private_key" {
  value     = tls_private_key.this.private_key_pem
  sensitive = false
}