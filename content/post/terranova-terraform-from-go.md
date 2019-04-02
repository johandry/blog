---
title: "Terranova: Using Terraform from Go with Terranova"
date: 2017-10-31T20:21:07-07:00
tags: ["Golang", "Terraform", "Terranova"]
toc: true
draft: true
---

[Terraform](http://terraform.io) is an amazing tool made by [HashiCorp](https://www.hashicorp.com) to describe infrastructure as a code. The use of Terraform is quite simple. After download the binary you need to create a terraform configuration file or files that describe the infrastructure to build. The first time you have to initialize terraform (`terraform init`) to download all the dependencies, then apply the changes (`terraform apply`). Any further change is as simple as modify the configuration file and apply the changes again. When the infrastructure is not needed, just destroy it (`terraform destroy`).

Many developers automate terraform tasks by using the binary with a script or a program and that’s totally fine. However if you are coding in Go and Terraform is made in Go (free and available on [GitHub](https://github.com/hashicorp/terraform)), why not use the Terraform packages instead of the binary?

One reason - and, to me, maybe the most important - to use the Terraform package instead of the binary is to provide to the users one single executable file to build and change the infrastructure. In a regular scenario the user have to download the Terraform binary, the configuration files (maybe more than one) and the instructions or a script to automate the process. Too many files, steps and dependencies, right?

The use of the Terraform package is simple once you are familiar with it. In order to make it simpler and easier to you, I will explain how to use the Go package **[Terranova](https://github.com/johandry/terranova)**.

## How to use the Terranova library

There are several objects needed by Terranova and Terraform to work:

- **Code**: It's basically the content of the configuration file, it may be a plain text or a Go template. This is the Infrastructure as a code.
- **Providers**: A Provider is the interface between terraform and the underlying platform which is usually an IaaS (i.e. AWS, GCP, MS Azure, VMWare), PaaS (i.e. Heroku) or SaaS (i.e. DNSimple). The entire list is here: https://www.terraform.io/docs/providers/
- **Provisioners**: The Provisioners are used to execute scripts on a local or remote machine, transfer files to remote machines and handling of configuration managers (i.e. Check, Salt). To know more or get the entire list, check this out: https://www.terraform.io/docs/provisioners/
- **Variables**: The Code may have references to terraform variables. This may be optional as we can handle variables in different ways in the Go code.
- **State**: This is final state of the infrastructure when the build or a change is done. It's important to keep the state in a save place to apply the further changes or destroy everything that was built.

The first step is to get and import the package:

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
  variable "count"    { default = 2 }
  variable "key_name" {}
  provider "aws" {
    region        = "us-west-2"
  }
  resource "aws_instance" "server" {
    instance_type = "t2.micro"
    ami           = "ami-6e1a0117"
    count         = "${var.count}"
    key_name      = "${var.key_name}"
  }
  provisioner "file" {
    content     = "ami used: ${self.ami}"
    destination = "/tmp/file.log"
  }
`
}
```

In this example the Terraform code is to create the given number of AWS EC2 Ubuntu instances on the AWS region `us-west-2`.

Now we are ready to create an instance of the [`Platform` struct](https://github.com/johandry/terranova/blob/master/platform.go) using `NewPlatform()` passing the code as second parameter.

```go
func main() {
  platform, err := terranova.NewPlatform("", code)
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

* `file`: used to copy files or directories from the local machine to the newly created resource.
* `local-exec`: invokes a local executable after a resource is created on the local machine.
* `remote-exec`: invokes a script on a remote resource after it is created. 

If you use Chef or Salt as configuration managers, there are provisioners for both that can configure the newly created resource.

The only Provisioner that is loaded by default is `null_resource`. It's a resource that allows you to configure provisioners that are not directly associated with a single existing resource.

### Variables

The Terraform code allows you to define and use variables and variables that behaves like constants. This may be an optional feature if you use Go templates to create the Terraform code with static values or assigning default values to variables. If you are using plain text code, just like in this example, then variables is something you may want to use.

In this example we have two variables: `count` and `key_name`. Only `count` has a default value so not adding a value for `key_name` will cause an error.

```go
func main() {
  count := 1
  keyName := "username"
    ...
  platform.Var("count", 1)
  platform.Var("key_name", keyName)
}
```

Other option would be to use the function `AddVars()` which is kind of handy when you get the variables after unmarshall a JSON, Yaml or Toml file with the values.

```go
func main() {
  vars := map[string]interface{}{
    "count":    "1",
    "key_name": "username",
  }
  ...
  platform.AddVars(vars)
}
```

### Apply changes

Once you have the Platform with the Code, Providers, Provisioners and the Variables loaded you can apply the code to the platform to get the changes done. It could be to modify the infrastructure (i.e. increasing or decreasing the number of instances) or to destroy everything done.

To achive this we use the function `Apply(bool)` which receives a boolean to know if the actions to apply are to destroy/terminate the infrastructure or not.

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
    log.Panicf("Fail to load the state of the platform from %s. %s", stateFilename, err)
  }
    ...
    // here is where Apply() is call
    ...
  if err := platform.WriteStateFile(stateFilename); err != nil {
    log.Fatalf("Fail to save the state of the platform to file %s. %s", stateFilename, err)
  }
}
```

And that's basically all you need to use Terranova to help you to use Terraform from a Go program. The entire code looks like this:

```go
package main

import (
  "log"
  "strconv"

  "github.com/hashicorp/terraform/builtin/provisioners/file"
  "github.com/johandry/terranova"
  "github.com/terraform-providers/terraform-provider-aws/aws"
)

var code string

const stateFilename = "aws-ec2-ubuntu.tfstate"

func main() {
  count := 1
  keyName := "username"

  platform, err := terranova.NewPlatform("", code)
  if err != nil {
    log.Fatalf("Fail to initialize the platform. %s", err)
  }

  platform.AddProvider("aws", aws.Provider())
  platform.AddProvisioner("file", file.Provisioner())

  platform.Var("count", strconv.Itoa(count))
  platform.Var("key_name", keyName)
  
  if _, err := platform.ReadStateFile(stateFilename); err != nil {
    log.Panicf("Fail to load the initial state of the platform from file %s. %s", stateFilename, err)
  }

  terminate := (count == 0)
    if err := platform.Apply(terminate); err != nil {
    log.Fatalf("Fail to apply the changes to the platform. %s", err)
  }

  if err := platform.WriteStateFile(stateFilename); err != nil {
    log.Fatalf("Fail to save the final state of the platform to file %s. %s", stateFilename, err)
  }
}

func init() {
  code = `
  variable "count" 		{ default = 2 }
  variable "key_name" {}
  provider "aws" {
    region        = "us-west-2"
  }
  resource "aws_instance" "server" {
    instance_type = "t2.micro"
    ami           = "ami-6e1a0117"
    count         = "${var.count}"
    key_name      = "${var.key_name}"
  }
  provisioner "file" {
    content     = "ami used: ${self.ami}"
    destination = "/tmp/file.log"
  }
`
}
```

### Modules and Terraform version



## How Terranova is made

Then we need a Go struct to store everything terraform needs to build or change an infrastructure such as:

* **Code**: It's basically the content of the configuration file, it may be a plain text or a Go template. This is the Infrastructure as a code.
* **List of Providers**: A Provider is the interface between terraform and the underlying platform which is usually an IaaS (i.e. AWS, GCP, MS Azure, VMWare), PaaS (i.e. Heroku) or SaaS (i.e. DNSimple)
* **List of Provisioners**: The Provisioners are used to execute scripts on a local or remote machine, transfer files to remote machines and handling of configuration managers (i.e. Check, Salt)
* **List of variables**: The code may have references to terraform variables. This may be optional as we can handle variables in different ways in the Go code.
* **State**: This is final state of the infrastructure when the build or a change is done. It's important to keep the state to apply the further changes or destroy everything that was built.

  There are other objects that are required by terraform and it's optional to store them, check the [`Platform` struct](https://github.com/johandry/terranova/blob/master/platform.go) below:

```go
// Platform is the platform to be managed by Terraform
type Platform struct {
  Path             string
  Code             string
  Providers        map[string]terraform.ResourceProvider
  Provisioners     map[string]terraform.ResourceProvisioner
  vars             map[string]interface{}
  state            *terraform.State
  plan             *terraform.Plan
  mod              *module.Tree
  context          *terraform.Context
  providerResolver terraform.ResourceProviderResolver
  provisioners     map[string]terraform.ResourceProvisionerFactory
}
```

`Providers` and `Provisioners` are exported to the user, `providerResolver` and `provisioners` are basically the same information but as Terraform expect them. It's required to create a function to create the latest from the formers. Check [`updateProviders()`](https://github.com/johandry/terranova/blob/master/provider.go) and [`updateProvisioners()`](https://github.com/johandry/terranova/blob/master/provisioner.go)

The `New()` function is to make a platform instance with initial default values:

```go
// New return an instance of Platform
func New(path string, code string) (*Platform, error) {
  platform := &Platform{
    Path: path,
    Code: code,
  }

  ...

  return platform, nil
}
```

In `New()` is initialized the platform with default providers or provisioners that most of the time are required. Check [`defaultProvisioners()`](https://github.com/johandry/terranova/blob/master/provisioner.go) and [`updateProviders()`](https://github.com/johandry/terranova/blob/master/provider.go) to add those you need but are not by default in Platform struct.

The way Terraform use the code is through a terraform module. We need to create a function to create a terraform module from the code. The code has to be saved in a temporally file, that's the reason of the `path` variable, to store the temporally file there. If `path` is not set, a temporally directory will be created.

```
func (p *Platform) setModule() (*module.Tree, error) {
  var cfgPath = p.Path
  if len(cfgPath) == 0 {
    tmpDir, err := ioutil.TempDir("", "terranova")
    if err != nil {
      return nil, err
    }
    cfgPath = tmpDir
    defer os.RemoveAll(cfgPath)
  }

  if len(p.Code) > 0 {
    cfgFileName := filepath.Join(cfgPath, "main.tf")
    cfgFile, err := os.Create(cfgFileName)
    if err != nil {
      return nil, err
    }
    _, err = io.Copy(cfgFile, strings.NewReader(p.Code))
    if err != nil {
      return nil, err
    }
    cfgFile.Close()
    defer os.Remove(cfgFileName)
  }

  mod, err := module.NewTreeModule("", cfgPath)
  if err != nil {
    return nil, err
  }
  modStorage := &getter.FolderStorage{
    StorageDir: filepath.Join(cfgPath, ".tfmodules"),
  }
  if err = mod.Load(modStorage, module.GetModeNone); err != nil {
    return nil, err
  }
  p.mod = mod

  return p.mod, nil
}
```

Now we are ready to complete the `New()` function:

```
func New(path string, code string) (*Platform, error) {
  platform := &Platform{
    Path: path,
    Code: code,
  }
  platform.Providers = defaultProviders()
  platform.updateProviders()
  platform.Provisioners = defaultProvisioners()
  platform.updateProvisioners()

  if _, err := platform.setModule(); err != nil {
    return platform, err
  }

  return platform, nil
}
```

The `terraform apply` workflow is like this:

1. Create the Terraform Context. A Context is a struct with some configuration parameters required by terraform such as the current state (initially is an empty state), list of variables, the module that has the configuration file or code, list of providers and provisioners.
2. Create the execution plan for that context and refresh it.
3. Apply the changes

Let's create an `Apply` function to implement these actions:

```
func (p *Platform) Apply(destroy bool) error {
  if p.context == nil {
    if _, err := p.Context(destroy); err != nil {
      return err
    }
  }

  if _, err := p.context.Plan(); err != nil {
    return err
  }

  if _, err := p.context.Refresh(); err != nil {
    return err
  }

  state, err := p.context.Apply()
  if err != nil {
    return err
  }
  p.state = state

  return nil
}
```

To create the terraform context is basically to use `terraform.NewContext(ctxOpts)` function passing the context options struct with the current state, list of variables, the module, list of providers and provisioners. Check [`Context()`](https://github.com/johandry/terranova/blob/master/platform.go)

```
ctxOpts := &terraform.ContextOpts{
  Destroy:          destroy,
  State:            p.state,
  Variables:        p.vars,
  Module:           p.mod,
  ProviderResolver: p.providerResolver,
  Provisioners:     p.provisioners,
}

ctx, err := terraform.NewContext(ctxOpts)
```

When `Apply()` finish, the final state will be stored at the `state` variable. It's important to keep this state if we are planning to change the infrastructures or destroy it. It may be useful to save this state to a file and terraform provide us two functions for that:

* `func (terraform) WriteState(state, buffer) error`: Save the state into a buffer that can be saved to a file later.
* `func (terraform) ReadState(buffer) (state, error)`: The buffer has the state in a text form (i.e. read from a file) and ReadState store that buffer into the state variable to be used by terraform later.

## Providers and Provisioners

Some default providers that you can load by default are:

* `template` at `github.com/terraform-providers/terraform-provider-template/template`
* `null` at `github.com/terraform-providers/terraform-provider-null/null`

It’s up to you to include more providers, all that your code requires. For example, if you will create an AWS platform you need to import `github.com/terraform-providers/terraform-provider-aws/aws` and add the provider.

You can create a function to adds them like this:

```
// AddProvider adds a new provider to the providers list
func (p *Platform) AddProvider(name string, provider terraform.ResourceProvider) *Platform {
  if p.Providers == nil {
    p.Providers = defaultProviders()
  }
  p.Providers[name] = provider

  p.updateProviders()

  return p
}
```

A possible default list of provisioners are: `local-exec`, `remote-exec` and `file`, all of them are located in the Terraform library (`github.com/hashicorp/terraform/builtin/provisioners`).

If it's required to add more provisioners, do a function named `AddProvisioner()` very similar to `AddProvider()`

