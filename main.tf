terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
      tls = {
      source = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

variable "region" {
  type = string
  
}
variable "vpcrange" {
  type = string
}
variable "vpc_subnet_fw" {
  type = string
  
}
variable "vpc_subnet_windows" {
  type = string
}

provider "aws" {
  region = var.region
    shared_config_files = ["/home/nachi/.aws/config"]
    shared_credentials_files = ["/home/nachi/.aws/credentials"]
}

#AMI 
data "aws_ami" "pf_sense" {
  most_recent = true
  filter {
    name = "name"
    values = ["pfSense-plus-ec2-23.*"]
  }

}

data "aws_ami" "windows_image" {
  most_recent = true
  filter {
    name = "name"
    values = ["Windows_Server-2022-English-Full-Base-2023.*"]
  }
}

#Network 
resource "aws_vpc" "this" {
    cidr_block = var.vpcrange
    tags = {
        name = "lab_vpc_02"
    }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

#Subnet Windows 
resource "aws_subnet" "windows" {
  vpc_id = aws_vpc.this.id
  cidr_block = var.vpc_subnet_windows

}

#Subnet Firewall 
resource "aws_subnet" "pfsense" {
   vpc_id = aws_vpc.this.id
   cidr_block = var.vpc_subnet_fw
}


#Route PFFirewall 
resource "aws_route_table" "pf_route" {
    vpc_id = aws_vpc.this.id
    route {
        cidr_block ="0.0.0.0/0"
        gateway_id = aws_internet_gateway.this.id
    }
    route {
         cidr_block ="192.168.6.0/24"
        gateway_id = "local"
    }
}
resource "aws_route_table_association" "this" {
  subnet_id = aws_subnet.pfsense.id
  route_table_id = aws_route_table.pf_route.id
}
#Security group 
resource "aws_security_group" "pf_sg" {
  vpc_id = aws_vpc.this.id
}

resource "aws_security_group" "pf_sg_w" {
  vpc_id = aws_vpc.this.id
}
resource "aws_vpc_security_group_ingress_rule" "outside" {
  security_group_id = aws_security_group.pf_sg_w.id
  ip_protocol = "all"
  cidr_ipv4 = "192.168.6.0/26"
}
resource "aws_vpc_security_group_egress_rule" "rdp" {
  from_port = 3389
  to_port = 3389
  security_group_id = aws_security_group.pf_sg_w.id
  ip_protocol = "tcp"
  cidr_ipv4 = "192.168.6.10/32"
}

resource "aws_vpc_security_group_egress_rule" "rdpnat" {
  security_group_id = aws_security_group.pf_sg.id
  ip_protocol = "all"
  cidr_ipv4 = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "comming" {
  security_group_id = aws_security_group.pf_sg.id
  ip_protocol = "all"
  cidr_ipv4 = "0.0.0.0/0"
}




#PfFirewall 
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "aws_key_pair" "this" {
  key_name = "lab02_nacho"
  public_key = tls_private_key.this.public_key_openssh
  
}
resource "aws_instance" "firewall"{
    ami = data.aws_ami.pf_sense.id
    instance_type = "t3a.medium"
    key_name = aws_key_pair.this.key_name
        network_interface {
        network_interface_id = aws_network_interface.public_ip.id
        device_index = 0
  }


}
#Nic 1 
resource "aws_network_interface" "private_ip" {
  subnet_id = aws_subnet.windows.id 
  attachment {
    instance = aws_instance.firewall.id
    device_index = 1
    }
  depends_on = [ 
    aws_instance.firewall
   ]
  private_ips = ["192.168.6.11"]
  source_dest_check = false
  security_groups = [aws_security_group.pf_sg_w.id]


}

#Nic 2
resource "aws_network_interface" "public_ip" {
  subnet_id = aws_subnet.pfsense.id
  private_ips = ["192.168.6.68"]
  source_dest_check = false
  security_groups = [aws_security_group.pf_sg.id]

}
resource "aws_eip" "this" {
  instance = aws_instance.firewall.id
  domain = "vpc"
}
resource "aws_eip_association" "this" {
  network_interface_id = aws_network_interface.public_ip.id
  allocation_id = aws_eip.this.id
}
#Windows Server 
resource "aws_instance" "windows_ec2"{
    ami = data.aws_ami.windows_image.id
    instance_type = "t2.micro"
    key_name = aws_key_pair.this.key_name
     network_interface {
    network_interface_id = aws_network_interface.private_ip_windows.id
    device_index = 0
    }
    



}

#NIC 
resource "aws_network_interface" "private_ip_windows" {
  subnet_id = aws_subnet.windows.id 


  private_ips = ["192.168.6.10"]

  security_groups = [aws_security_group.sg_windows.id]


}

#Windows Route 
resource "aws_route_table" "ws_route" {
   vpc_id = aws_vpc.this.id
    route {
        cidr_block ="0.0.0.0/0"
        network_interface_id = aws_network_interface.private_ip.id
    }
    route {
         cidr_block ="192.168.6.0/24"
        gateway_id = "local"
    }
}
resource "aws_route_table_association" "this_ws" {
  subnet_id = aws_subnet.windows.id
  route_table_id = aws_route_table.ws_route.id
}
#Windows Security group 
resource "aws_security_group" "sg_windows" {
  vpc_id = aws_vpc.this.id
}

resource "aws_vpc_security_group_egress_rule" "windows_rule" {
  security_group_id = aws_security_group.sg_windows.id
  ip_protocol = "all"
  cidr_ipv4 = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "windows_rule_rdp" {
  security_group_id = aws_security_group.sg_windows.id
  from_port = 3389
  to_port = 3389
  ip_protocol = "tcp"
  cidr_ipv4 = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "windows_rule_rdp_udp" {
  security_group_id = aws_security_group.sg_windows.id
  from_port = 3389
  to_port = 3389
  ip_protocol = "udp"
  cidr_ipv4 = "192.168.6.11/32"
}


