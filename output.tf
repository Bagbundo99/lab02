output "private_key" {
  value     = tls_private_key.this.private_key_pem
  sensitive = true
}

output "ip_firewall" {
  value =  aws_eip.this
  description = "Info of elastic IP firewall"
}