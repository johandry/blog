---
title: "Terranova: Using Terraform from Go"
date: 2017-10-31T20:21:07-07:00
tags: ["Golang", "Terraform", "Terranova"]
toc: true
---

[Terraform](http://terraform.io) is an amazing tool made by [HashiCorp](https://www.hashicorp.com) to describe infrastructure as a code. Terraform allow us to build, change, and do versioning of the infrastructure safely and efficiently. The use of Terraform is quite simple, after download the binary you need to create a terraform configuration file or files to describe the infrastructure to build. The first time you have to initialize terraform (`terraform init`) to download all the dependencies and then apply the changes (`terraform apply`). Any further change is as simple as modify the configuration file and apply the changes again. When the infrastructure is not needed, you just destroy it (`terraform destroy`).

Many developers automate terraform tasks calling the binary from a script or a program and that’s totally fine. However if you are coding in Go and knowing that Terraform is made in Go (free and available on [GitHub](https://github.com/hashicorp/terraform)), why not use the Terraform packages instead of the binary?

One reason - and, to me, maybe the most important - to use the Terraform package instead of the binary is to provide to the users one single executable file to build and change the infrastructure. In a regular scenario the user have to download the Terraform binary, the configuration files (usually more than one) and the instructions or a script automating the process. Too many files, steps and dependencies, right?

The use of the Terraform package is simple once you are familiar with it. In order to make it simpler and easier to you, I will explain how to use the Go package **[Terranova](https://github.com/johandry/terranova)**.

## How to use the Terranova library

There are several objects needed by Terranova and therefore by Terraform to work:

- **Code**: It's basically the content of the configuration file(s), it may be a plain text or a Go template. This is the Infrastructure as a code.
- **Providers**: A Provider is the interface between terraform and the underlying platform which is usually an IaaS (i.e. AWS, GCP, MS Azure, VMWare), PaaS (i.e. Heroku) or SaaS (i.e. DNSimple). The entire list is here: https://www.terraform.io/docs/providers/
- **Provisioners**: The Provisioners are used to execute scripts on a local or remote machine, transfer files to remote machines and handling of configuration managers (i.e. Check, Salt). To know more or get the entire list, check this out: https://www.terraform.io/docs/provisioners/
- **Variables**: The Code may have references to terraform variables. This may be optional as we can handle variables in different ways in the Go code.
- **State**: This is final state of the infrastructure when the build or a change is done. It's important to keep the state in a save place to apply the further changes or destroy everything that was built.

The first step is to get and import the Terranova package:

```bash
go get -u github.com/johandry/terranova
```

```go
import (
  "github.com/johandry/terranova"
)
```

Then lets work on each of the needed objects.

### Code

To create the Terraform Code we need a string variable to store it either as a plain text or a template but to keep to simple lets use plain text.

```go
var code string

func init() {
  code = `
  variable "count"            {}
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
}
```

In this example the Terraform code is to create a given number of AWS EC2 Ubuntu instances on the AWS region `us-west-2`. Also to create a Key Pair made from the public key.

Now we are ready to create an instance of the [`Platform` struct](https://github.com/johandry/terranova/blob/master/platform.go) using `NewPlatform()` passing the code as a parameter.

```go
func main() {
  platform, err := terranova.NewPlatform(code)
  if err != nil {
    log.Fatalf("Fail to initialize the platform. %s", err)
  }
}
```

### Providers

The Terraform code used in this example uses the AWS Provider, so we have to make this provider available to the platform first getting and importing the package, then using the `AddProvider()` function.

```bash
go get -u github.com/terraform-providers/terraform-provider-aws/aws
```

```go
import (
    ...
  "github.com/terraform-providers/terraform-provider-aws/aws"
)
```

```go
func main() {
    ...
  platform.AddProvider("aws", aws.Provider())
}
```

Your code can include more than one provider, for example, if the code is to create host in the  cloud or different platforms this code has to import all the packages and add those that are needed by the Terraform code.

The only Provider that is loaded by default is `null`. It's a resource that allows you to configure provisioners that are not directly associated with a single existing resource.

### Provisioners

Every Terraform code uses at least one Provider, but not all the Terraform codes uses a provisioner. In this example we are using the provisioner `file`, so same as with providers, we have to get it, import it and add it.

```bash
go get -u github.com/hashicorp/terraform/builtin/provisioners/file
```

```go
import (
    ...
  "github.com/hashicorp/terraform/builtin/provisioners/file"
)
```

```go
func main() {
    ...
  platform.AddProvisioner("file", file.Provisioner())
}
```

The most common and useful provisioner to use are:

- `file`: used to copy files or directories from the local machine to the newly created resource.
- `local-exec`: invokes a local executable after a resource is created on the local machine.
- `remote-exec`: invokes a script on a remote resource after it is created.

Look at the sample code below to know how to import the package and to call the method `AddProvisioner()`  for these Provisioners:

```go
import (
  "github.com/hashicorp/terraform/builtin/provisioners/file"
  localexec "github.com/hashicorp/terraform/builtin/provisioners/local-exec"
  remoteexec "github.com/hashicorp/terraform/builtin/provisioners/remote-exec"
)
...
platform.AddProvisioner("file", file.Provisioner())
platform.AddProvisioner("local-exec", localexec.Provisioner())
platform.AddProvisioner("remote-exec", remoteexec.Provisioner())
```

If you use Chef or Salt as configuration managers, there are provisioners for both that can configure the newly created resource.

### Variables

The Terraform code allows you to define and use variables and variables that behaves like constants. This may be an optional feature if you use Go templates to create the Terraform code with static values or assigning default values to variables. If you are using plain text code, just like in this example, then variables is something you may want to use.

In this example we have three variables: `count`, `public_key_file` and `private_key_file`. The key files variables has a default value so not adding a value for `count` will cause an error.

```go
func main() {
  count := 1
    ...
  platform.Var("count", count)
}
```

Other option would be to use the function `BindVars()` which is handy when you get the variables after unmarshalling a JSON, Yaml or Toml file with the values.

```go
func main() {
  vars := map[string]interface{}{
    "count": 1,
  }
  ...
  platform.BindVars(vars)
}
```

### Apply changes

Once you have the Platform with the Code, Providers, Provisioners and the Variables loaded you can apply the code to the platform to get the changes done. It could be to modify the infrastructure (i.e. increasing or decreasing the number of instances) or to destroy everything done.

To achieve this we use the function `Apply(bool)` which receives a boolean to know if the actions to apply are to destroy/terminate the infrastructure or not.

```go
func main() {
    ...
  terminate := (count == 0)
  if err := platform.Apply(terminate); err != nil {
    log.Fatalf("Fail to apply the changes to the platform. %s", err)
  }
}
```

### State

After applying the changes the infrastructure state also change. This state will be needed to do more changes to this infrastructure later, such as increase or decrease the number of instances, or destroy everything to save money.

So, as you have notice, it's important to make this state persistent saving it into a file after applying the changes and to load the state (if any) before applying the changes.

```go
const stateFilename = "aws-ec2-ubuntu.tfstate"

func main() {
  ...
  if _, err := platform.ReadStateFile(stateFilename); err != nil {
    log.Fatalf("Fail to load the state of the platform from %s. %s", stateFilename, err)
  }
    ...
    // here is where Apply() is call
    ...
  if _, err := platform.WriteStateFile(stateFilename); err != nil {
    log.Fatalf("Fail to save the state of the platform to file %s. %s", stateFilename, err)
  }
}
```

And that's basically all you need to use Terranova to help you to use Terraform from a Go program. The entire code looks like this:

```go
package main

import (
  "log"
  "os"

  "github.com/hashicorp/terraform/builtin/provisioners/file"
  "github.com/johandry/terranova"
  "github.com/terraform-providers/terraform-provider-aws/aws"
)

var code string

const stateFilename = "aws-ec2-ubuntu.tfstate"

func main() {
  count := 1

  platform, err := terranova.NewPlatform(code).
    AddProvider("aws", aws.Provider()).
    AddProvisioner("file", file.Provisioner()).
    Var("count", count).
    ReadStateFromFile(stateFilename)

  if err != nil {
    if os.IsNotExist(err) {
      log.Printf("[DEBUG] state file %s does not exists", stateFilename)
    } else {
      log.Fatalf("Fail to load the initial state of the platform from file %s. %s", stateFilename, err)
    }
  }

  terminate := (count == 0)
  if err := platform.Apply(terminate); err != nil {
    log.Fatalf("Fail to apply the changes to the platform. %s", err)
  }

  if _, err := platform.WriteStateFile(stateFilename); err != nil {
    log.Fatalf("Fail to save the final state of the platform to file %s. %s", stateFilename, err)
  }
}

func init() {
  code = `
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
}

```

This code example with a few more improvements is located in the [Terranova examples repository](https://github.com/johandry/terranova-examples/blob/master/aws/ec2/main.go).

The Terranova package is just an API that makes it easy to the Go developers to use the Terraform package made by Hashicorp but to use it is optional, you can use the Hashicorp's Terraform package directly just like Terranova does it.

There is an advantage of using Terranova vs using Hashicorp's Terraform directly. The Hashicorp's Terraform code change as well as their package contract and they are not forced to keep it because it's their code and what they produce and provide is Terraform binary, not the internal code. So, when Hashicorp changes the code and the contract, all of you using the Terraform code will have to do it as well. Having a package that works as as an interface to the Hashicorp Terraform code would help us to keep our code stable because others (and hopefully you too) will work on making the Terranova package using the latest changes of Terraform Go code.

Saying this, I invite you to help us to improve Terranova. If you find a bug or want to have a new feature, please, create a Pull Request and we'll include it.

This is not the last post about this topic, next post will be about how to use the Hashicorp Terraform Go just like Terranova uses it, and there will be a more about how to use your infrastructure code as a Go template, using Hooks to execute some actions for every Terraform activity such as logging, print output, update counters; and how to get values from your new infrastructure such as number of instances created/updated, IP or DNS addresses.