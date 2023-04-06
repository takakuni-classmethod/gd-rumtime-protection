data "http" "ifconfig" {
  url = "http://ipv4.icanhazip.com/"
}

######################################
# EKS Cluster Role Configuration
######################################
resource "aws_security_group" "eks_cluster" {
  name = "${local.prefix}-sg-eks-cluster"
  description = "${local.prefix}-sg-eks-cluster"

  tags = {
    Name = "${local.prefix}-sg-eks-cluster"
  }
}

resource "aws_security_group_rule" "eks_cluster_ingress_self" {
  security_group_id = aws_security_group.eks_cluster.id
  type = "ingress"
  from_port = 0
  to_port = 0
  protocol = "tcp"
  self = true
}

resource "aws_security_group_rule" "eks_cluster_egress_all" {
  security_group_id = aws_security_group.eks_cluster.id
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = [ "0.0.0.0/0" ]
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${local.prefix}-role-eks-cluster"
  assume_role_policy = file("${path.module}/iam_policy_document/assume_eks.json")

  tags = {
    Name = "${local.prefix}-role-eks-cluster"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_eks_cluster" "cluster" {
  name = "${local.prefix}-cluster"
  version = "1.25"
  role_arn = aws_iam_role.eks_cluster.arn
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler" ]

  vpc_config {
    subnet_ids = module.vpc.private_subnets
    # public_access_cidrs = concat(
    #   ["${chomp(data.http.ifconfig.response_body)}/32"],
    #   formatlist("%s/32", module.vpc.nat_public_ips)
    # )
    public_access_cidrs = ["${chomp(data.http.ifconfig.response_body)}/32"]
    endpoint_private_access = true
  }

  encryption_config {
    resources = [ "secrets" ]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }
}

######################################
# EKS Node Group Role Configuration
######################################
resource "aws_iam_role" "eks_node" {
  name               = "${local.prefix}-role-eks-node"
  assume_role_policy = file("${path.module}/iam_policy_document/assume_ec2.json")

  tags = {
    Name = "${local.prefix}-role-eks-node"
  }
}

resource "aws_iam_instance_profile" "eks_node" {
  role = aws_iam_role.eks_node.name
  name = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_node_worker_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_container_registry_readonly" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "node" {
  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = "${local.prefix}-node-group"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = module.vpc.private_subnets
  instance_types = ["t3.medium"]
  ami_type = "AL2_x86_64"
  capacity_type = "ON_DEMAND"
  disk_size = 20

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker_node_policy,
    aws_iam_role_policy_attachment.eks_node_cni_policy,
    aws_iam_role_policy_attachment.eks_node_container_registry_readonly
  ]
}

######################################
# EKS Node Group Role Configuration
######################################
resource "aws_eks_addon" "aws_guardduty_agent" {
  cluster_name = aws_eks_cluster.cluster.name
  addon_name = "aws-guardduty-agent"
  addon_version = "v1.0.0-eksbuild.1"
}