---
title: "Using Terraform Packages from Go"
date: 2017-10-31T20:21:07-07:00
tags: ["Golang", "Terraform"]
toc: true
draft: true
---

[Terraform](http://terraform.io) is a tool made by [HashiCorp](https://www.hashicorp.com) to describe infrastructure as a code. Therefore it's used for building, changing, and versioning infrastructure safely and efficiently.

The use of Terraform is quite simple. After download the binary you need to create a terraform configuration file that describe the infrastructure to build. The first time you have to initialize terraform (`terraform init`) otherwise just go and apply the changes (`terraform apply`). Any further change is as simple as modify the configuration file and apply the changes again. When it's not needed, just destroy it (`terraform destroy`).

Many developers automate terraform tasks by using the binary with a script and that’s totally fine. However Terraform is made in Go and the code is available on [GitHub](https://github.com/hashicorp/terraform) so, why not use the Terraform packages instead of the binary?

One - and maybe the most important - reason to use the Terraform package instead of the binary is to provide to the users one single executable file to build and change the infrastructure. In a regular scenario the user have to download the Terraform binary, the configuration files (maybe more than one) and the instructions or a script to automate the process. Too many files and dependencies right?

In this post I’ll explain how to use the Terraform code but if you feel lost check [Platformer](https://github.com/johandry/platformer/) Go Package and the [AWS example](https://github.com/johandry/platformer-examples)

There is a little problem with this: the vendors version. We'll use a terraform package version (i.e. `0.10.3`) that is the same version used by the a provisioner (i.e. AWS). If we want to use a second provisioner (i.e. Azure or vSphere) it may not use the same terraform version as AWS, so we have a versioning problem. To avoid this problem we'll use a dependency management tool like `govendor`, `glide` or `dep`, to have the right version of all the imported packages.

## How to use the Terraform library

The first step is to get the package:

    go get -u github.com/hashicorp/terraform/terraform

Then we need a structure to store everything terraform needs to build or change an infrastructure such as:

* **Code**: It's basically the content of the configuration file. The Infrastructure as a Code.
* **List of Providers**: A Provider the interface between terraform and the underlying platform which is usually an IaaS (i.e. AWS, GCP, MS Azure, VMWare), PaaS (i.e. Heroku) or SaaS (i.e. DNSimple)
* **List of Provisioners**: The Provisioner are used to execute scripts on a local or remote machine, transfer files to remote machines and handling of configuration managers (i.e. Check, Salt)
* **List of variables**: The code may have references to terraform variables. This may be optional as we can handle variables in different ways in the Go code.
* **State**: This is final state of the infrastructure when the build or a change is done. It's important to keep the state to apply the following changes or destroy everything that was built.

There are other objects that are required by terraform and it's optional to store them, check the [`Platformer` struct](https://github.com/johandry/platformer/blob/master/platformer.go) below:

```
// Platformer is the platform to be managed by Terraform
type Platformer struct {
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

`Providers` and `Provisioners` are exported to the user, `providerResolver` and `provisioners` are basically the same information but as Terraform expect them. It's required to create a function to create the latest from the formers. Check [`updateProviders()`](https://github.com/johandry/platformer/blob/master/provider.go) and [`updateProvisioners()`](https://github.com/johandry/platformer/blob/master/provisioner.go)

Would be useful to create a function to make a platformer instance like this:

```
// New return an instance of Platformer
func New(path string, code string) (*Platformer, error) {
  platformer := &Platformer{
    Path: path,
    Code: code,
  }

  ...

  return platformer, nil
}
```

In `New()` we can initialize the platformer with default providers or provisioners if some of them are always required. Check [`defaultProvisioners()`](https://github.com/johandry/platformer/blob/master/provisioner.go) and [`updateProviders()`](https://github.com/johandry/platformer/blob/master/provider.go).

The way Terraform use the code is through a terraform module. We need to create a function to create a terraform module from the code. The code has to be saved in a temporally file, that's the reason of the `path` variable, to store the temporally file there. If `path` is not set, a temporally directory will be created.

```
func (p *Platformer) setModule() (*module.Tree, error) {
  var cfgPath = p.Path
  if len(cfgPath) == 0 {
    tmpDir, err := ioutil.TempDir("", "platformer")
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
func New(path string, code string) (*Platformer, error) {
  platformer := &Platformer{
    Path: path,
    Code: code,
  }
  platformer.Providers = defaultProviders()
  platformer.updateProviders()
  platformer.Provisioners = defaultProvisioners()
  platformer.updateProvisioners()

  if _, err := platformer.setModule(); err != nil {
    return platformer, err
  }

  return platformer, nil
}
```

The `terraform apply` workflow is like this:

1. Create the Terraform Context. A Context is a struct with some configuration parameters required by terraform such as the current state (initially is an empty state), list of variables, the module that has the configuration file or code, list of providers and provisioners.
2. Create the execution plan for that context and refresh it.
3. Apply the changes

Let's create an `Apply` function to implement these actions:

```
func (p *Platformer) Apply(destroy bool) error {
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

To create the terraform context is basically to use `terraform.NewContext(ctxOpts)` function passing the context options struct with the current state, list of variables, the module, list of providers and provisioners. Check [`Context()`](https://github.com/johandry/platformer/blob/master/platformer.go)

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
func (p *Platformer) AddProvider(name string, provider terraform.ResourceProvider) *Platformer {
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