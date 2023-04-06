######################################
# KMS
######################################
resource "aws_kms_key" "eks" {
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy = templatefile("${path.module}/iam_policy_document/key_eks.json", {
    account_id = data.aws_caller_identity.self.account_id
  })
}

resource "aws_kms_alias" "eks" {
  target_key_id = aws_kms_key.eks.key_id
  name          = "alias/${local.prefix}/eks"
}