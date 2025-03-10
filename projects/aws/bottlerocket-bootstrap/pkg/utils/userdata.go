package utils

import (
	"context"
	"encoding/base64"
	"fmt"
	"io/fs"
	"io/ioutil"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/eks-anywhere-build-tooling/aws/bottlerocket-bootstrap/pkg/service"

	"github.com/pkg/errors"
	"gopkg.in/yaml.v2"
)

const (
	userDataFile      = "/.bottlerocket/host-containers/current/user-data"
	awsSecretsManager = "AWSSecretsManager"
)

type WriteFile struct {
	Path        string
	Owner       string
	Permissions string
	Content     string
}

type AWSSecretsManagerData struct {
	Provider string
	Prefix   string
	Chunks   int
}

type AWSSecretsManagerUserData struct {
	// This field is set by the CAPI provider.
	// It indicates whether this UserData is normal userdata, or a userdata that is stored remotely.
	UserDataType   string                `yaml:"user_data_type"`
	UserDataSource AWSSecretsManagerData `yaml:"secrets_manager_data"`
}

type UserData struct {
	// This field is set by the CAPI provider.
	// It indicates whether this UserData is normal userdata, or a userdata that is stored remotely.
	UserDataType string      `yaml:"user_data_type"`
	WriteFiles   []WriteFile `yaml:"write_files"`
	RunCmd       string      `yaml:"runcmd"`
}

func ResolveUserData() (*UserData, error) {
	fmt.Println("Reading userdata file")
	// read userdata from the file
	data, err := ioutil.ReadFile(userDataFile)
	if err != nil {
		return nil, errors.Wrap(err, "Error reading user data file")
	}
	return processUserData(data, service.NewSecretsManagerService())
}

func processUserData(data []byte, secretsManagerService service.SecretsManagerService) (*UserData, error) {
	userData := &UserData{}
	err := yaml.Unmarshal(data, userData)
	if err != nil {
		return nil, errors.Wrap(err, "Error unmarshalling user data")
	}
	fmt.Printf("\n%+v\n", userData)
	if userData.UserDataType == awsSecretsManager {
		// If this is a AWSSecretsManager typped UserData, parse it as AWSSecretsManagerUserData
		fmt.Println("The loaded userdata is referecing an external userdata, loading it...")
		awsSecretsManagerUserData := &AWSSecretsManagerUserData{}
		err = yaml.Unmarshal(data, awsSecretsManagerUserData)
		if err != nil {
			return nil, errors.Wrap(err, "Error unmarshalling user data")
		}
		bootstrapUserData, err := loadUserDataFromSecretsManager(awsSecretsManagerUserData, secretsManagerService)
		if err != nil {
			fmt.Printf("Error loading userdata from SecretsManager: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("Successfully loaded userdata from SecretsManager")
		return bootstrapUserData, nil
	} else {
		return userData, nil
	}
}

func loadUserDataFromSecretsManager(awsSecretsManagerUserData *AWSSecretsManagerUserData, secretManagerService service.SecretsManagerService) (*UserData, error) {
	compressedCloudConfigBinary := []byte{}
	for i := 0; i < awsSecretsManagerUserData.UserDataSource.Chunks; i++ {
		secretName := fmt.Sprintf("%s-%d", awsSecretsManagerUserData.UserDataSource.Prefix, i)
		secret, err := secretManagerService.GetSecretValue(context.TODO(), secretName)
		if err != nil {
			return nil, err
		}
		compressedCloudConfigBinary = append(compressedCloudConfigBinary, secret.SecretBinary...)
		secretManagerService.DeleteSecret(context.TODO(), secretName)
	}

	uncompressedData, err := GUnzipBytes(compressedCloudConfigBinary)
	if err != nil {
		return nil, err
	}
	base64UserDataString := string(uncompressedData)
	actualUserDataByte, err := base64.StdEncoding.DecodeString(base64UserDataString)

	if err != nil {
		return nil, err
	}

	acutalUserData := &UserData{}
	err = yaml.Unmarshal(actualUserDataByte, acutalUserData)
	if err != nil {
		return nil, errors.Wrap(err, "Error unmarshalling user data")
	}
	return acutalUserData, nil
}

func WriteUserDataFiles(userData *UserData) error {
	fmt.Println("Writing userdata write files")
	for _, file := range userData.WriteFiles {
		if file.Permissions == "" {
			file.Permissions = "0640"
		}
		perm, err := strconv.ParseInt(file.Permissions, 8, 64)
		if err != nil {
			return errors.Wrap(err, "Error converting string to int for permissions")
		}
		dir := filepath.Dir(file.Path)
		err = os.MkdirAll(dir, 0640)
		if err != nil {
			return errors.Wrap(err, "Error creating directories")
		}
		err = ioutil.WriteFile(file.Path, []byte(file.Content), fs.FileMode(perm))
		if err != nil {
			return errors.Wrapf(err, "Error creating file: %s", file.Path)
		}
		// get owner
		owners := strings.Split(file.Owner, ":")
		owner := owners[0]
		userDetails, err := user.Lookup(owner)
		if err != nil {
			return errors.Wrap(err, "Error getting user/group details ")
		}
		uid, _ := strconv.Atoi(userDetails.Uid)
		gid, _ := strconv.Atoi(userDetails.Gid)
		err = syscall.Chown(file.Path, uid, gid)
		if err != nil {
			return errors.Wrap(err, "Error running chown to set owners/groups")
		}
	}
	return nil
}
