---
title: "Using Terraform Packages From Go"
date: 2019-03-22T14:22:55-07:00
toc: true
draft: true
---

In a previous post I explain how to use Terranova which is a Go package to use the Terraform Go packages in a easy and simple way. This post is about how to use the Terraform Go packages directly, or in other words: How Terranova works.

## How to use Terraform directly

If you don't want to use Terranova and opt for using Terraform directly, the first step is to get the Terraform package and import it in your code.

```
go get -u github.com/hashicorp/terraform/terraform
```

```go
import "github.com/hashicorp/terraform/terraform"
```

Then would be useful to have a structure to store everything terraform needs to build or change an infrastructure such as:  Code, Providers, Provisioners, Variables and State.

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
variable "count" 		{ default = 2 }
variable "key_name" 	{}
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

func main() {
    v := map[string]interface{}{
        "count": 1,
        "key_name": "demo",
    }
    p := &Platformer{
        Code: 	   Code,
        Variables: v,
    }
}
```

In this example the Terraform code is to create the given number of AWS EC2 Ubuntu instances on the AWS region `us-west-2`.

Now, it's time to set the providers and provisioners needed by the Terraform code or configuration files, so make sure to download them all and import them in your code. In this example, if your configuration file uses the **AWS** provider and the **file** provisioner, you have to:

```bash
go get -u github.com/terraform-providers/terraform-provider-aws/aws
go get -u github.com/hashicorp/terraform/builtin/provisioners/file
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

Next step is to create the Terraform module. You have to save the configuration files into a temporal directory then create the module to make it load the saved configuration files. The Terraform code could be in multimple or a single file, but if you have multiple files it's ok to merge them into one with no specific order.

```go
// Create a temporal directory or use any directory
tfrDir, err := ioutil.TempDir("", ".terraformer")
if err != nil {
    log.Fatalln(err)
}
defer os.RemoveAll(tfrDir)
// Save the code into a single or multimple files 
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

If you own the entire Terraform code, it may be no need to validate it with `mod.Validate()` but if the code contain some user input, it may be a good idea to validate it.

Having ready the Terraform module you are ready to create the Terraform context. The Terraform context contain almost everything you have in your structure. It will also tell to Terroform if the action will be to create or to destroy, this is set in the `terraform.ContextOpts.Destroy` parameter. In your code, it would be an user input.

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

*Optionally you can use Hooks to report the status of Terraform or collect metrics. The Hooks are not part of this description but you can look at the code of Terranova. Optionally you may also validate the context and print out the different errors or warnings. Again, this is not covered here but you can look at the code of Terranova*

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

// Retrive the state from the Terraform context
tfState := ctx.State()
if err := terraform.WriteState(tfState, state); err != nil {
    log.Fatalf("Failed to retrive the state. %s", err)
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
```