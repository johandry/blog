# Using Terraform Packages from Go

## What’s Terraform?

[Terraform](http://terraform.io) is a tool made by [HashiCorp](https://www.hashicorp.com) for building, changing, and versioning infrastructure safely and efficiently. As Terraform allows us to describe the infrastructure as a code, it’s used by many developers, testers and DevOps engineers to create development and testing environments. But also it’s used in production environments to maintain the desired state of the environment.

If you haven’t used before, please, read about it and use it. It’s an awesome tool and there are plenty of documentation and books about it. Meanwhile I’ll give you a quick summary. 

The use of Terraform is quite simple. After download the binary for your OS you need to create a terraform configuration file that describe the infrastructure you need. If this is the first time you have to initialize terraform (`terraform init`) otherwise just go and apply the changes (`terraform apply`). Terraform will create the infrastructure as defined in the configuration file but if you want to do a change just modify the file and apply the changes again. When you are done you may destroy everything, all is described in code and can be done again.

Many developers automate terraform tasks by using the binary from the code and that’s fine. However Terraform is made in Go and the Terraform packages are available on [GitHub](https://github.com/hashicorp/terraform) so, why not use the Terraform packages instead of the binary?

## Why use Terraform code instead of the binary?

The initial reason of this was the need to provide to the users one single binary to manage the required infrastructure. Not using the Terraform code would mena the user needs to download the Terraform binary, the configuration files (may be more than one) and the instructions or a script for automation. Too many files right? Wouldn’t be better to download just a binary for the user OS and execute it?

There may be more reasons to justify the use of the Terraform code. I use it to learn more about Go and how Terraform works. 

## Deja la muela and show me the code

In this post I’ll explain how to use the Terraform code but if you feel lost check [Platformer](https://github.com/johandry/platformer/). It’s a Go Package that uses the Terraform code but it have not been used in production yet, so use it _only_ for educational purposes to create your own Go library or application. It’s still on research so, if you find something that can be improved or wrong, please, [email me](johandry@gmail.com) or create a PR.

One of the biggest issues with this library is the version of the vendors. This code uses `terraform` package version `0.10.3` (not the latest version) but the latest version of a provisioner may not be the correct for this terraform version. To avoid this versioning issues use a vendoring Go tool (i.e. `govendor`, `glide` or `dep`) to make sure you have the right version of all the imported packages.

## How to use the Terraform library

Make sure you have installed the package:

    go get -u github.com/hashicorp/terraform/terraform

The high level flow is like follows, and it is coded in `func (p *Platformer) Apply(destroy bool) error` in the file `platformer.go` of Platformer.

1. Create the Terraform Context with some configuration parameters
2. Create the execution plan for the previous context and refresh it.
3. Apply the changes

The configuration parameters (on step #1) are the following:

- List of providers
- List of provisioners
- Current State
- Variables
- Assign a storage module or directory where all the Terraform templates are

### Providers

The default list of providers I have identified are: `template` (github.com/terraform-providers/terraform-provider-template/template) and `null` (github.com/terraform-providers/terraform-provider-null/null). Check the function `func (p *Platformer) updateProviders() terraform.ResourceProviderResolver` on `provider.go` and also the entire file.

It’s up to you to include more providers, all that your code requires. For example, if you will create an AWS platform or using the AWS resource in a Terraform template, you need to import `github.com/terraform-providers/terraform-provider-aws/aws` and add the provider in the same way as it’s done on function `func (p *Platformer) AddProvisioner(name string, provisioner terraform.ResourceProvisioner) *Platformer`

### Provisioners

The default list of provisioners I’ve found are: `local-exec`, `remote-exec` and `file`, all of them are located in the Terraform library (github.com/hashicorp/terraform/builtin/provisioners). It may be required to add more provisioners, to do so run the code as in the function `func (p *Platformer) AddProvisioner(name string, provisioner terraform.ResourceProvisioner) *Platformer` on `provisioner.go` as well.

### Variables

Optionally, if your Terraform template contains them, you can add variables to the Terraform context. Provide a map of interfaces `map[string]interface{}` with all the variable/value pairs and assign it to the Terraform context to the variable `Variables`.

### Storage Module

To specify the Terraform template you can provide the path where all these templates (or maybe just one) are. Or, you can have the Terraform template embedded in your code. The former is done by passing the directory where all the templates are to `github.com/hashicorp/terraform/config/module`.`func NewTreeModule(name, dir string) (*Tree, error)`, create a `github.com/hashicorp/go-getter`.`FolderStorage` struct with the same directory and assign it to `StorageDir`, finally load the templates with the method `func (t *Tree) Load(s getter.Storage, mode GetMode) error` of the instance of `*Tree` returned from the previous `NewTreeModule`.

The second option is to embed the Terraform template code in your Go code. Save the template to a temporal file in a temporal directory. The next steps is the same as explained above. Do not forget to delete the temporal file and directory (you may use `defer` for this).

All these code is located in the function `func (p *Platformer) setModule() (*module.Tree, error)` on file `platformer.go`

### Current State

The current state need to be assigned to the Terraform context into the field `State` before any action with that context (i.e. Plan)

After the plan is applied the output is an state file. This state file need to be saved into memory or a file so the next time you apply another change to the platform, Terraform would know in what state it is.

Initially (if no previous state is provided) need to be created an empty state. That’s done with the function `github.com/hashicorp/terraform/terraform`.`func NewState() *State`. If a state is provided you can load/read it with the function `func ReadState(src io.Reader) (*State, error)`.

After the changes are done, get the final state using the function `func WriteState(d *State, dst io.Writer) error` so you can assign it to a variable (save it to memory) or save it to a file or database.

## Examples

The git repository https://github.com/johandry/platformer-examples contain an example of how to create a few EC2 instances in AWS using this library.

More examples for other infrastructures/clouds will be added to the same directory.

## Sources

All this research was done initially form the Gist of Greg Osuri (https://gist.github.com/gosuri/a1233ad6197e45d670b3), then a lot was obtained from the Terraform documentation (https://godoc.org/github.com/hashicorp/terraform) and source code (https://github.com/hashicorp/terraform).
