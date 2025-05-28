job "template-manager" {
  datacenters = ["${aws_az1}", "${aws_az2}"]
  node_pool  = "default"
  priority = 70

  group "template-manager" {
    network {
      port "template-manager" {
        static = "5009"
      }
    }
    service {
      name = "template-manager"
      port = "template-manager"

      check {
        type         = "grpc"
        name         = "health"
        interval     = "20s"
        timeout      = "5s"
        grpc_use_tls = false
        port         = "template-manager"
      }
    }

    task "start" {
      driver = "raw_exec"

      resources {
        memory     = 1024
        cpu        = 256
      }

      env {
        AWS_ACCOUNT_ID               = "${account_id}"
        AWS_REGION                   = "${AWSREGION}"
        AWS_ECR_REPOSITORY           = "e2bdev/base"
        OTEL_TRACING_PRINT           = false
        ENVIRONMENT                  = "dev"
        TEMPLATE_AWS_BUCKET_NAME     = "${BUCKET_FC_TEMPLATE}"
        TEMPLATE_BUCKET_NAME         = "${BUCKET_FC_TEMPLATE}"
        OTEL_COLLECTOR_GRPC_ENDPOINT = "localhost:4317"
      }

      config {
        command = "/bin/bash"
        args    = ["-c", " chmod +x local/template-manager && local/template-manager --port 5009"]
      }

      artifact {
        source      = "s3://${CFNSOFTWAREBUCKET}.s3.${AWSREGION}.amazonaws.com/template-manager"
      }
    }
  }
}
