---
title: "Using Terraform Packages From Go"
date: 2019-03-22T14:22:55-07:00
toc: true
draft: true
---

In a previous post I explain how to use Terranova which is a Go package to use the Terraform Go packages in a easy and simple way. This post is about how to use the Terraform Go packages directly, or in other words: How Terranova works.

## How to use Terraform directly

If you don't want to use Terranova and opt for using Terraform directly, the first step is to import the Terraform package in your code.

```go
import "github.com/hashicorp/terraform/terraform"
```

It's recommended to setup the project to use Go modules because this How-To works with Terraform `0.11.9`, if you try to use the latest version (i.e. `0.11.13`) some components may not work, for example the variables.

Edit your `go.mod` file to add this line in the `require` section, then execute `go mod tidy` or `go test ./…` to download the Terraform package:

```go
require (
  github.com/hashicorp/terraform v0.11.9-beta1
)
```

In the Go code would be useful to have a struct to store everything Terraform needs to build or change an infrastructure such as:  Code, Providers, Provisioners, Variables and State.

For example:

```go
// Platform store all the information needed by Terraform
type Platform struct {
  Code             string
  Providers        map[string]terraform.ResourceProvider
  Provisioners     map[string]terraform.ResourceProvisioner
  Variables        map[string]interface{}
  State            *terraform.State
}
```

Each of these fields in the struct are explained in the previous post but here they are again:

- **Code**: It's basically the content of the configuration file, it may be a plain text or a Go template. This is the Infrastructure as a code.
- **Providers**: A Provider is the interface between terraform and the underlying platform which is usually an IaaS (i.e. AWS, GCP, MS Azure, VMWare), PaaS (i.e. Heroku) or SaaS (i.e. DNSimple)
- **Provisioners**: The Provisioners are used to execute scripts on a local or remote machine, transfer files to remote machines and handling of configuration managers (i.e. Check, Salt)
- **Variables**: The code may have references to terraform variables. This may be optional as we can handle variables in different ways in the Go code.
- **State**: This is final state of the infrastructure when the build or a change is done. It's important to keep the state to apply the further changes or destroy everything that was built.

When this structure is created or initialized, you have to assign the Terraform code to execute and the map of variables with the values.

To create the Terraform Code we need a string variable to store it either as a plain text or a template but to keep to simple lets use plain text.

In the version of Terraform we are using, the variables is a map of `interface{}` but this change in the latest version of Terraform.

```go
const Code = `
variable "count"            { default = 2 }
variable "public_key_file"  { default = "~/.ssh/id_rsa.pub" }
variable "private_key_file" { default = "~/.ssh/id_rsa" }
locals {
  public_key    = "${file(pathexpand(var.public_key_file))}"
  private_key   = "${file(pathexpand(var.private_key_file))}"
}
provider "aws" {
  region        = "us-west-2"
}
resource "aws_instance" "server" {
  instance_type = "t2.micro"
  ami           = "ami-6e1a0117"
  count         = "${var.count}"
  key_name      = "server_key"

  provisioner "file" {
    content     = "ami used: ${self.ami}"
    destination = "/tmp/file.log"

    connection {
      user        = "ubuntu"
      private_key = "${local.private_key}"
    }
  }
}
resource "aws_key_pair" "keypair" {
  key_name    = "server_key"
  public_key  = "${local.public_key}"
}
`

func main() {
  p := &Platform{
    Code: Code,
    Vars: map[string]interface{}{
      "count": count,
    },
  }

  if len(pubKeyFile) != 0 {
    p.Vars["public_key_file"] = pubKeyFile
  }
  if len(privKeyFile) != 0 {
    p.Vars["private_key_file"] = privKeyFile
  }
}
```

In this example the Terraform code is to create the given number of AWS EC2 Ubuntu instances on the AWS region `us-west-2`. Also generate the Key Pair from the given private and public keys, this Key Pair is required to login to the EC2 instances.

Now it's time to set the providers and provisioners needed by the Terraform code or configuration files, so make sure to download them all and import them in your code. In this example, if your configuration file uses the **AWS** provider and the **file** provisioner, you have to add an entry in the `go.mod` file for the AWS Provider or use the `go get` command to download it. There is no need to go-get or add the file provisioner because it's internal to Terraform and it's already downloaded.

```go
require (
  ...
  github.com/terraform-providers/terraform-provider-aws v1.60.0
)
```

And in your code:

```go
import "github.com/terraform-providers/terraform-provider-aws/aws"
import "github.com/hashicorp/terraform/builtin/provisioners/file"
```

All these providers and provisioners have to be added to the Terraform context:

```go
// Providers:
ctxProviders := make(map[string]terraform.ResourceProviderFactory)
ctxProviders["aws"] = terraform.ResourceProviderFactoryFixed(aws.Provider())
providerResolvers := terraform.ResourceProviderResolverFixed(ctxProviders)

// Provisioners:
provisionersFactory := make(map[string]terraform.ResourceProvisionerFactory)
provisionersFactory["file"] = func() (terraform.ResourceProvisioner, error) {
  return file.Provisioner(), nil
}
```

Every Terraform code uses at least one Provider, but not all the Terraform codes uses a provisioner.

Next step is to create the Terraform module. You have to save the configuration files into a temporal directory then create the module to make it load the saved configuration files. The Terraform code could be in multiple or a single file, but if you have multiple files it's ok to merge them into one with no specific order.

```go
// Create a temporal directory or use any directory
tfrDir, err := ioutil.TempDir("", ".myterraform")
if err != nil {
  log.Fatalln(err)
}
defer os.RemoveAll(tfrDir)
// Save the code into a single or multiple files
filename := filepath.Join(tfrDir, "main.tf")
configFile, err := os.Create(filename)
if err != nil {
  log.Fatalln(err)
}
defer configFile.Close()

// Copy the Terraform template from p.Code into the new file
if _, err = io.Copy(configFile, bytes.NewReader([]byte(p.Code)); err != nil {
  log.Fatalln(err)
}

// Create the Terraform module
mod, err := module.NewTreeModule("", tfrDir)
if err != nil {
  log.Fatalln(err)
}

// Create the Storage pointing to where the Terraform code is
storageDir := filepath.Join(tfrDir, "modules")
s := module.NewStorage(storageDir, nil)
s.Mode = module.GetModeNone // or module.GetModeGet

// Finally make the module load the
if err := mod.Load(s); err != nil {
  log.Fatalf("Error loading modules. %s", err)
}

// Optionally, you can validate the loaded code if it has some user input
if err := mod.Validate().Err(); err != nil {
  log.Fatalf("Failed Terraform code validation. %s", err)
}
```

Having ready the Terraform module you are ready to create the Terraform context. The Terraform context contain almost everything you have in your structure. It will also tell to Terraform if the action will be to create or to destroy, this is set in the `terraform.ContextOpts.Destroy` parameter. In your code, it would be an user input.

```go
destroy := false

ctxOpts := terraform.ContextOpts{
  Destroy:          destroy,
  State:            p.State,
  Variables:        p.Variables,
  Module:           mod,
  ProviderResolver: providerResolvers,
  Provisioners:     provisionersFactory,
}

ctx, err := terraform.NewContext(&ctxOpts)
if err != nil {
  log.Fatalf("Error creating context. %s", err)
}
```

You can use Hooks to report the status of Terraform or collect metrics. The Hooks are not part of this article but you can look at the code of Terranova. Also you may validate the context and print out the different errors or warning, but again this is not covered here and you can look at the code of Terranova

Before execute the action to apply the code, we have to execute a Refresh and a Plan. Like this:

```go
if _, err := ctx.Refresh(); err != nil {
  log.Fatalln(err)
}
if _, err := ctx.Plan(); err != nil {
  log.Fatalln(err)
}
if _, err = ctx.Apply(); err != nil {
  log.Fatalln(err)
}
```

After applying the code, you can get the current state with `ctx.State()` this state should be persistent, save it to a file to use it the next time you execute this code, so Terraform knows in what state the infrastructure is and update the required changes. Otherwise, Terraform will try to create everything again and may fail due to duplicate or existing resources.

```go
var state bytes.Buffer
stateFile := "./trn.state"

// Retrieve the state from the Terraform context
tfState := ctx.State()
if err := terraform.WriteState(tfState, state); err != nil {
  log.Fatalf("Failed to retrieve the state. %s", err)
}
// Save the state to the local file 'trn.state'
if err = ioutil.WriteFile(stateFile, state.Bytes(), 0644); err != nil {
  log.Fatalf("Fail to save the state to %q. %s", stateFile, err)
}
```

The previous code is to save the code but we are not reading the state the next time we execute it, so add some code to read the state file and add it to your structure. This code should go right after create and initialize the `Platform` structure.

```go
// If the file exists, read the state from the state file
if _, errStat := os.Stat(stateFile); os.IsExist(errStat) {
  stateB, err := ioutil.ReadFile(stateFile)
  if err != nil {
    log.Fatalf("Fail to read the state from %q", stateFile)
  }
  state = *bytes.NewBuffer(stateB)

  // Get the Terraform state from the state file content
  tfState, err := terraform.ReadState(state)
  if err != nil {
    log.Fatalln(err)
  }
  p.State = tfState
}

```

And this is it. We can polish a little bit the code by reading the variable `keyname` and `count` from the user and if it's `0` destroy the infrastructure.

The entire code looks like this:

```go
package main

import (
  "bytes"
  "flag"
  "io"
  "io/ioutil"
  "log"
  "os"
  "path/filepath"
  "strings"

  "github.com/hashicorp/terraform/builtin/provisioners/file"
  "github.com/hashicorp/terraform/config/module"
  "github.com/hashicorp/terraform/terraform"
  "github.com/terraform-providers/terraform-provider-aws/aws"
)

// Code is the Terraform code to execute
const Code = `
variable "count"            { default = 2 }
variable "public_key_file"  { default = "~/.ssh/id_rsa.pub" }
variable "private_key_file" { default = "~/.ssh/id_rsa" }
locals {
  public_key    = "${file(pathexpand(var.public_key_file))}"
  private_key   = "${file(pathexpand(var.private_key_file))}"
}
provider "aws" {
  region        = "us-west-2"
}
resource "aws_instance" "server" {
  instance_type = "t2.micro"
  ami           = "ami-6e1a0117"
  count         = "${var.count}"
  key_name      = "server_key"

  provisioner "file" {
    content     = "ami used: ${self.ami}"
    destination = "/tmp/file.log"

    connection {
      user        = "ubuntu"
      private_key = "${local.private_key}"
    }
  }
}
resource "aws_key_pair" "keypair" {
  key_name    = "server_key"
  public_key  = "${local.public_key}"
}
`

const (
  stateFile = "tf.state"
)

var (
  count       int
  pubKeyFile  string
  privKeyFile string
)

// Platform store all the information needed by Terraform
type Platform struct {
  Code         string
  Vars         map[string]interface{}
  Providers    map[string]terraform.ResourceProvider
  Provisioners map[string]terraform.ResourceProvisioner
  State        *terraform.State
}

func main() {
  flag.IntVar(&count, "count", 2, "number of instances to create. Set to '0' to terminate them all.")
  flag.StringVar(&pubKeyFile, "pub", "", "public key file to create the AWS Key Pair")
  flag.StringVar(&privKeyFile, "priv", "", "private key file to connect to the new AWS EC2 instances")
  flag.Parse()

  var state bytes.Buffer

  p := &Platform{
    Code: Code,
    Vars: map[string]interface{}{
      "count": count,
    },
  }

  if len(pubKeyFile) != 0 {
    p.Vars["public_key_file"] = pubKeyFile
  }
  if len(privKeyFile) != 0 {
    p.Vars["private_key_file"] = privKeyFile
  }

  // If the file exists, read the state from the state file
  if _, errStat := os.Stat(stateFile); errStat == nil {
    stateB, err := ioutil.ReadFile(stateFile)
    if err != nil {
      log.Fatalf("Fail to read the state from %q", stateFile)
    }
    state = *bytes.NewBuffer(stateB)

    // Get the Terraform state from the state file content
    if p.State, err = terraform.ReadState(&state); err != nil {
      log.Fatalln(err)
    }
  }

  // Create a temporal directory or use any directory
  tfDir, err := ioutil.TempDir("", ".tf")
  if err != nil {
    log.Fatalln(err)
  }
  defer os.RemoveAll(tfDir)
  // Save the code into a single or multiple files
  filename := filepath.Join(tfDir, "main.tf")
  configFile, err := os.Create(filename)
  if err != nil {
    log.Fatalln(err)
  }
  defer configFile.Close()

  // Copy the Terraform template from p.Code into the new file
  if _, err = io.Copy(configFile, strings.NewReader(p.Code)); err != nil {
    log.Fatalln(err)
  }

  // Create the Terraform module
  mod, err := module.NewTreeModule("", tfDir)
  if err != nil {
    log.Fatalln(err)
  }

  // Create the Storage pointing to where the Terraform code is
  storageDir := filepath.Join(tfDir, "modules")
  s := module.NewStorage(storageDir, nil)
  s.Mode = module.GetModeNone // or module.GetModeGet

  // Finally make the module load the
  if err := mod.Load(s); err != nil {
    log.Fatalf("Failed loading modules. %s", err)
  }

  // Optionally, you can validate the loaded code if it has some user input
  if err := mod.Validate().Err(); err != nil {
    log.Fatalf("Failed Terraform code validation. %s", err)
  }

  // Add Providers:
  ctxProviders := make(map[string]terraform.ResourceProviderFactory)
  // ctxProviders["null"] = terraform.ResourceProviderFactoryFixed(null.Provider())
  ctxProviders["aws"] = terraform.ResourceProviderFactoryFixed(aws.Provider())
  providerResolvers := terraform.ResourceProviderResolverFixed(ctxProviders)

  // Add Provisioners:
  provisionersFactory := make(map[string]terraform.ResourceProvisionerFactory)
  provisionersFactory["file"] = func() (terraform.ResourceProvisioner, error) {
    return file.Provisioner(), nil
  }

  destroy := (count == 0)

  ctxOpts := terraform.ContextOpts{
    Destroy:          destroy,
    State:            p.State,
    Variables:        p.Vars,
    Module:           mod,
    ProviderResolver: providerResolvers,
    Provisioners:     provisionersFactory,
  }

  ctx, err := terraform.NewContext(&ctxOpts)
  if err != nil {
    log.Fatalf("Failed creating context. %s", err)
  }

  if _, err := ctx.Refresh(); err != nil {
    log.Fatalln(err)
  }
  if _, err := ctx.Plan(); err != nil {
    log.Fatalln(err)
  }
  if _, err := ctx.Apply(); err != nil {
    log.Fatalln(err)
  }

  // Retrieve the state from the Terraform context
  p.State = ctx.State()
  if err := terraform.WriteState(p.State, &state); err != nil {
    log.Fatalf("Failed to retrieve the state. %s", err)
  }
  // Save the state to the local file 'tf.state'
  if err = ioutil.WriteFile(stateFile, state.Bytes(), 0644); err != nil {
    log.Fatalf("Fail to save the state to %q. %s", stateFile, err)
  }
}
```