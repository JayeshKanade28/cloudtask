//Terraform code
provider "aws" {
  region  = "ap-south-1"
  profile = "jayesh_kanade_mine"
}


// Generating key
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "task1-key"
  public_key = "${tls_private_key.example.public_key_openssh}"
}

// Generating Security group
resource "aws_security_group" "task1-sg" {
  name        = "task1-sg"
  description = "Allow TLS inbound traffic"
  vpc_id      = "vpc-f7ffe29f"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task1-sg"
  }
}


// Creating instance 
resource "aws_instance" "task1-instance" {
  ami 		= "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name 	= "${aws_key_pair.generated_key.key_name}"
  security_groups = [ "task1-sg" ] 

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.example.private_key_pem}"
    host     = aws_instance.task1-instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "task1 instance"
  }

}

// Creating extra volume
resource "aws_ebs_volume" "task1-ebs" {
  availability_zone = aws_instance.task1-instance.availability_zone
  size              = 1

  tags = {
    Name = "task1-ebs"
  }
}

// Attaching extra volume to the instance
resource "aws_volume_attachment" "task1-attach" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.task1-ebs.id}"
  instance_id = "${aws_instance.task1-instance.id}"
  force_detach = true
}

// Output of instance IP on console
output "myos_ip" {
  value = aws_instance.task1-instance.public_ip
}

// Saving IP of instance
resource "null_resource" "nulllocal2"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.task1-instance.public_ip} > publicip.txt"
  	}
}

// partitioning and formatting HD
resource "null_resource" "nullremote3"  {

depends_on = [
    aws_volume_attachment.task1-attach,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.example.private_key_pem}"
    host     = aws_instance.task1-instance.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/JayeshKanade28/cloudtask.git /var/www/html/"
    ]
  }
}



// Here we specify the bucket
resource "aws_s3_bucket" "git-bucket" {

    depends_on = [
      null_resource.nullremote3
    ]

    bucket = "task1-bucket-97309743"
    acl = "public-read"

    provisioner "local-exec" {
	command = "git clone https://github.com/JayeshKanade28/cloudtask.git git-image"
    }

    provisioner "local-exec" {
	when = destroy
	command = "rmdir /Q /S git-image"
    }
 
    tags = {
	Name        = "task1-bucket-97309743"
	Environment = "Dev"
    }
    force_destroy = true
}


// adding github-image to S3 bucket
resource "aws_s3_bucket_object" "image-bucket-object" {
  depends_on = [
     aws_s3_bucket.git-bucket

  ]
  acl	= "public-read"
  bucket = "${aws_s3_bucket.git-bucket.bucket}"
  key = "index.html"
  source = "git-image/img_lights.jpg"
  content_type = "image or jpg"
  //etag = "${md5(file("git-image/img_lights.jpg"))}"
}

locals {
  s3_origin_id = "S3-${aws_s3_bucket.git-bucket.bucket}"
}



// Create Cloudfront distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.git-bucket.bucket_domain_name
    origin_id   = "${local.s3_origin_id}"
  }
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "git-bucket-CF"
  
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"
    forwarded_values {
       query_string = false

      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.example.private_key_pem}"
    host     = aws_instance.task1-instance.public_ip
  }

  provisioner "remote-exec"{
    inline = [
      "sudo su <<EOF",
      "sudo sed -i '10i <img src='http://${self.domain_name}/${aws_s3_bucket_object.image-bucket-object.key}' width='400' height='380'>' /var/www/html/index.html",
      "EOF",
     ]	

  }

  tags = {
    Environment = "production"
  }
  
}

output "opcdn" {
  value = aws_cloudfront_distribution.s3_distribution
}


// Launching the site on chrome
resource "null_resource" "nulllocal1"  {


depends_on = [
    aws_cloudfront_distribution.s3_distribution,
  ]

	provisioner "local-exec" {
	    command = "chrome  ${aws_instance.task1-instance.public_ip}"
  	}
	
	provisioner "local-exec" {
	    command = "chrome  http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.image-bucket-object.key}"
  	}
	
}
