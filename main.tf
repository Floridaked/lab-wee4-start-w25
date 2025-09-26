data "aws_availability_zones" "available" {
  state = "available"
}

# configure version of aws provider plugin
# https://developer.hashicorp.com/terraform/language/terraform#terraform
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.0.0"
}

# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# https://developer.hashicorp.com/terraform/language/values/locals
locals {
  project_name = "lab_week_4"
}

# get the most recent ami for Debian
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami
data "aws_ami" "debian" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["debian-*-amd64-*"]
  }
}

# Create a VPC
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
resource "aws_vpc" "web" {
  cidr_block = "10.0.0.0/16"
  # enable dns enable_dns_hostnames

  tags = {
    Name = "project_vpc"
    # add project name using local
  }
}

# Create a public subnet
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
# To use the free tier t2.micro ec2 instance you have to declare an AZ
# Some AZs do not support this instance type
resource "aws_subnet" "web" {
  vpc_id     = aws_vpc.web.id
  cidr_block = "10.0.1.0/24"
  # set availability zone
  availability_zone = data.aws_availability_zones.available.names[0]
  # add public ip on launch
  map_public_ip_on_launch = true

  tags = {
    Name = "Web"
    # add project name using local
    project = local.project_name
  }
}

# Create internet gateway for VPC
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
resource "aws_internet_gateway" "web_gw" {
  # add vpc
  vpc_id = aws_vpc.web.id

  tags = {
    Name = "Web"
    # add project name using local
    Project = local.project_name
  }
}

# create route table for web VPC 
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
resource "aws_route_table" "web" {
  # add vpc 
  vpc_id = aws_vpc.web.id

  tags = {
    Name = "web-route"
    # add project name using local
    Project = local.project_name
  }
}

# add route to to route table
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route
resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.web.id
  destination_cidr_block = "0.0.0.0/0"
  # add gateway id
  gateway_id = aws_internet_gateway.web_gw.id
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
resource "aws_route_table_association" "web" {
  # add subnet id
  subnet_id      = aws_subnet.web.id
  route_table_id = aws_route_table.web.id
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "web" {
  name        = "allow_ssh"
  description = "allow ssh from home and work"
  # add vpc id
  vpc_id = aws_vpc.web.id

  ingress {
    description = "SSH from anywhere (lab)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Web"
    # add project name using local
    Project = local.project_name
  }
}



# use an existing key pair on host machine with file func
# if we weren't adding the public key in the cloud-init script we could import a public 
# using the aws_key_pair resource block
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair
# resource "aws_key_pair" "local_key" {
#   key_name   = "web-key"
#   public_key = file("~/.ssh/aws.pub")
# }

# create the ec2 instance
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
resource "aws_instance" "web" {
  # use ami provided by data block above
  ami = data.aws_ami.debian.id
  # set instance type
  instance_type = "t2.micro"

  subnet_id = aws_subnet.web.id
  # add vpc security group 
  vpc_security_group_ids = [aws_security_group.web.id]

  # key_name = aws_key_pair.local_key.key_name

  # add user datat for cloud-config file in scripts directory
  user_data = file("${path.module}/scripts/cloud-config.yaml")
  tags = {
    Name = "Web"
    # add project name using local
    Project = local.project_name
  }
}

# print public ip and dns to terminal
# https://developer.hashicorp.com/terraform/language/values/outputs
output "instance_ip_addr" {
  description = "The public IP and dns of the web ec2 instance."
  value = {
    "public_ip" = aws_instance.web.public_ip
    "dns_name"  = aws_instance.web.public_dns
  }
}
