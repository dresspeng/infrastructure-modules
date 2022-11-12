package test

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"

	test_shell "github.com/gruntwork-io/terratest/modules/shell"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func TestTerraformMongodbUnitTest(t *testing.T) {
	t.Parallel()

	bashCode := fmt.Sprint(`terragrunt init;`)
	command := test_shell.Command{
		Command: "bash",
		Args:    []string{"-c", bashCode},
	}
	shellOutput := test_shell.RunCommandAndGetOutput(t, command)
	fmt.Printf("\nStart shell output: %s\n", shellOutput)

	id := uuid.New().String()[0:7]
	bastion := true
	account_name := os.Getenv("AWS_PROFILE")
	aws_region := os.Getenv("AWS_REGION")
	environment_name := fmt.Sprintf("scraper-mongodb-%s", id)
	common_name := strings.ToLower(fmt.Sprintf("%s-%s-%s", account_name, aws_region, environment_name))
	bucket_name_mongodb := fmt.Sprintf("%s-mongodb", common_name)
	bucket_name_pictures := fmt.Sprintf("%s-pictures", common_name)

	vpc_id := terraform.Output(t, &terraform.Options{TerraformDir: "../../vpc"}, "vpc_id")
	default_security_group_id := terraform.Output(t, &terraform.Options{TerraformDir: "../../vpc"}, "default_security_group_id")
	private_subnets := terraform.OutputList(t, &terraform.Options{TerraformDir: "../../vpc"}, "private_subnets")
	public_subnets := terraform.OutputList(t, &terraform.Options{TerraformDir: "../../vpc"}, "public_subnets")
	vpc_cidr_block := terraform.Output(t, &terraform.Options{TerraformDir: "../../vpc"}, "vpc_cidr_block")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "",
		Vars: map[string]interface{}{
			"aws_region":             aws_region,
			"data_storage_name":      common_name,
			"private_subnets":        private_subnets,
			"public_subnets":         public_subnets,
			"vpc_security_group_ids": []string{default_security_group_id},
			"vpc_id":                 vpc_id,
			"vpc_cidr_block":         vpc_cidr_block,
			"common_tags": map[string]string{
				"Account":     account_name,
				"Region":      aws_region,
				"Environment": environment_name,
			},
			"ami_id":         "ami-09d3b3274b6c5d4aa",
			"instance_type":  "t2.micro",
			"user_data_path": "mongodb.sh",
			"user_data_args": map[string]string{
				"HOME":                 "/home/ec2-user",
				"UID":                  "1000",
				"bucket_name_mongodb":  bucket_name_mongodb,
				"bucket_name_pictures": bucket_name_pictures,
				"mongodb_version":      "6.0.1",
			},
			"bastion": bastion,
		},
		VarFiles: []string{"terraform_override.tfvars"},

		RetryableTerraformErrors: map[string]string{
			"port 22: Connection refused":   "SSH Connection refused",
			"port 22: Connection timed out": "SSH Connection timed out",
		},
	})

	defer func() {
		if r := recover(); r != nil {
			// destroy all resources if panic
			terraform.Destroy(t, terraformOptions)
		}
		test_structure.RunTestStage(t, "cleanup_mongodb", func() {
			terraform.Destroy(t, terraformOptions)
		})
	}()

	test_structure.RunTestStage(t, "deploy_mongodb", func() {
		terraform.InitAndApply(t, terraformOptions)
	})

	test_structure.RunTestStage(t, "validate_ssh", func() {
		publicInstanceIPBastion := terraform.OutputList(t, terraformOptions, "ec2_instance_bastion_public_ip")[0]
		privateInstanceIPMongodb := terraform.Output(t, terraformOptions, "ec2_instance_mongodb_private_ip")
		keyPair := ssh.KeyPair{
			PublicKey:  terraform.OutputList(t, terraformOptions, "public_key_openssh")[0],
			PrivateKey: terraform.OutputList(t, terraformOptions, "private_key_openssh")[0],
		}

		// upload key to bastion to connect to private instance
		bashCode := fmt.Sprintf(`ssh-keyscan -H %s >> ~/.ssh/known_hosts;`, publicInstanceIPBastion)
		bashCode += fmt.Sprintf(`sudo chmod 400 %s.pem;`, common_name)
		bashCode += fmt.Sprintf(`scp -i "%s.pem" %s.pem ec2-user@%s:/home/ec2-user;`, common_name, common_name, publicInstanceIPBastion)
		command := test_shell.Command{
			Command: "bash",
			Args:    []string{"-c", bashCode},
		}
		shellOutput, err := test_shell.RunCommandAndGetOutputE(t, command)
		if err != nil {
			fmt.Printf("\nUpload to bastion error: %s\n", err.Error())
		}
		fmt.Printf("\nUpload to bastion output: %s\n", shellOutput)

		sshToPrivateHost(t, publicInstanceIPBastion, privateInstanceIPMongodb, &keyPair)
	})

	test_structure.RunTestStage(t, "validate_mongodb", func() {
		s3bucketMongodbArn := terraform.Output(t, terraformOptions, "s3_bucket_mongodb_arn")
		s3bucketpicturesArn := terraform.Output(t, terraformOptions, "s3_bucket_pictures_arn")
		assert.Equal(t, fmt.Sprintf("arn:aws:s3:::%s", bucket_name_mongodb), s3bucketMongodbArn)
		assert.Equal(t, fmt.Sprintf("arn:aws:s3:::%s", bucket_name_pictures), s3bucketpicturesArn)
	})
}

func sshToPrivateHost(t *testing.T, publicInstanceIP string, privateInstanceIP string, keyPair *ssh.KeyPair) {
	publicHost := ssh.Host{
		Hostname:    publicInstanceIP,
		SshKeyPair:  keyPair,
		SshUserName: "ec2-user",
	}
	privateHost := ssh.Host{
		Hostname:    privateInstanceIP,
		SshKeyPair:  keyPair,
		SshUserName: "ec2-user",
	}

	maxRetries := 15
	timeBetweenRetries := 30 * time.Second

	description := fmt.Sprintf("SSH to private host %s via public host %s", privateInstanceIP, publicInstanceIP)
	expectedText := "Hello, World"
	command := fmt.Sprintf("echo -n '%s'", expectedText)
	retry.DoWithRetry(t, description, maxRetries, timeBetweenRetries, func() (string, error) {
		actualText, err := ssh.CheckPrivateSshConnectionE(t, publicHost, privateHost, command)
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(actualText) != expectedText {
			return "", fmt.Errorf("Expected SSH command to return '%s' but got '%s'", expectedText, actualText)
		}
		return "", nil
	})

	description = fmt.Sprintf("Check mount S3 bucket of private host %s via public host %s", privateInstanceIP, publicInstanceIP)
	expectedText = "s3fs fuse.s3fs /mys3bucket"
	command = `df -Th /mys3bucket | tail -n +2 |  awk '{ print $1, $2, $7 }'`
	retry.DoWithRetry(t, description, maxRetries, timeBetweenRetries, func() (string, error) {
		actualText, err := ssh.CheckPrivateSshConnectionE(t, publicHost, privateHost, command)
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(actualText) != expectedText {
			return "", fmt.Errorf("Expected SSH command to return '%s' but got '%s'", expectedText, actualText)
		}
		return "", nil
	})

	description = fmt.Sprintf("Check docker container mongodb of private host %s via public host %s", privateInstanceIP, publicInstanceIP)
	expectedText = "scraper-mongodb"
	command = `sudo docker ps --format '{{.Names}}'`
	retry.DoWithRetry(t, description, maxRetries, timeBetweenRetries, func() (string, error) {
		actualText, err := ssh.CheckPrivateSshConnectionE(t, publicHost, privateHost, command)
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(actualText) != expectedText {
			return "", fmt.Errorf("Expected SSH command to return '%s' but got '%s'", expectedText, actualText)
		}
		return "", nil
	})

	description = fmt.Sprintf("Check mongodb port of private host %s via public host %s", privateInstanceIP, publicInstanceIP)
	port := 27017
	expectedText = fmt.Sprintf("Open %d", port)
	command = fmt.Sprintf(`(echo >/dev/tcp/%s/%d) &>/dev/null && echo "Open %d" || echo "Close %d"`, privateHost.Hostname, port, port, port)
	retry.DoWithRetry(t, description, maxRetries, timeBetweenRetries, func() (string, error) {
		actualText, err := ssh.CheckPrivateSshConnectionE(t, publicHost, privateHost, command)
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(actualText) != expectedText {
			return "", fmt.Errorf("Expected SSH command to return '%s' but got '%s'", expectedText, actualText)
		}
		return "", nil
	})
}
