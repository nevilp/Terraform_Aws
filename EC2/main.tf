resource "aws_instance" "my_ec2" {
  ami                    = "ami-0f918f7e67a3323f0"   # Replace with Ubuntu AMI
  instance_type          = "t2.large"
  subnet_id              = "subnet-076ed2b434bdb07bb"
  vpc_security_group_ids = ["sg-0f2ea22b2bd634102"]
  key_name               = "docker-ec2"

  user_data = file("user_data.sh")

  tags = {
    Name = "MyEC2Instance"
  }
}
