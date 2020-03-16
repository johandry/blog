---

title: "Building a Kubernetes Client in Go"
date: 2020-03-15T11:56:02-08:00
---

# Building a Kubernetes Client in Go

`defer Conclusion()`

Now I have the task to build a Kubernetes client in Go. The requirements are something like this: having an existing Kubernetes cluster it's required a program to create or replace resources such as ConfigMaps, Secrets, Services and Deployments.

If you know the resources to create, for example a ConfigMap, it's not a big deal, just use the Kubernetes clientset (`kubernetes.Clientset`) from `github.com/kubernetes/client-go` and there are plenty of examples like those in the [examples](https://github.com/kubernetes/client-go/tree/master/examples) directory from the same package. Here is a simple example to create a ConfigMap resource:

```go
import (
  corev1 "k8s.io/api/core/v1"
  "k8s.io/apimachinery/pkg/api/errors"
  metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
  "k8s.io/client-go/kubernetes"
  "k8s.io/client-go/tools/clientcmd"
)

...

config, _ := clientcmd.BuildConfigFromFlags("", kubeconfigPath)
clientset, _ := kubernetes.NewForConfig(config)
configMapData := make(map[string]string, 0)
uiProperties := `
color.good=purple
color.bad=yellow
allow.textmode=true
`
configMapData["ui.properties"] = uiProperties
configMap := corev1.ConfigMap{
  TypeMeta: metav1.TypeMeta{
    Kind:       "ConfigMap",
    APIVersion: "v1",
  },
  ObjectMeta: metav1.ObjectMeta{
    Name:      "game-data",
    Namespace: "game",
  },
  Data: configMapData,
}

var cm *corev1.ConfigMap
if _, err := clientset.CoreV1().ConfigMaps("game").Get("game-data", metav1.GetOptions{}); errors.IsNotFound(err) {
  cm, _ = clientset.CoreV1().ConfigMaps("game").Create(&configMap)
} else {
  cm, _ = clientset.CoreV1().ConfigMaps("game").Update(&configMap)
}
```

*Do not ignore the errors, I did it just to simplify the code.*

This code gets the same results as creating or applying with `kubectl` the following ConfigMap file:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: game-data
  namespace: game
data:
  ui.properties: |
    color.good=purple
    color.bad=yellow
    allow.textmode=true
```

If these were the requirements then problem solved. To create/update known resources you just need to:

1. Create the `config` from the kubeconfig file 
2. Create the `clientset` from the `config`
3. Create the resource(s) (`configMap`) using the appropriate API structure (`core/v1` and `meta/v1`)
4. Identify if the resource exists using `Get()` and the right resource method. If it exist, use `Create()`, otherwise use `Update()`

Simple, right? :slightly_smiling_face:

Unfortunately, the requirements changed (weird, they never change, right?); the resources are unknown in advance and are provided to the client by a file, a Go template or a HTTP URL.

So, goodbye to the clientset and the awesome data structures from `k8s.io/api` (we'll see you later tho) and welcome to the vast collection of Kubernetes data structures and methods.

By the time I'm writing this post there is no much documentation about how to do this, so I had to dug into the deep code of Kubernetes and other tools to get ...

## A Kubernetes client to apply resources of any type

In case you are in hurry and just want to read code, no problema, go to the GitHub repository `johandry/kube-client`.

<u>Important</u>, I'm ignoring most of the errors in the code, **<u>don't do that</u>**, I just doing it to simplify the code. Refer to the code in the repository to get the entire code and error handling.

The plan to get this done is almost similar to the steps above, so let's get started with the step #1:

### (1) Create the Factory

Let's encapsulate all the configuration data such as the kubeconfig path and context into a configuration struct.

Checking the code of `kubectl` and the `apply` command, they use a `Factory` interface and structure to provide the REST Configuration, a REST Mapper, a Discovery and REST Client, and a Builder among other things. The good news is, all these methods and what they provide can be obtained from the configuration struct and as it will create all these objects for us, let's rename it to `Factory`.

```go
type factory struct {
  KubeConfig    string
  Context       string
}
```

The first and the foundation for all the other methods is the `ClientConfig`, to create it we will need (1) the path to the kubeconfig file and the context, but this is not the only way, (2) the program may be running in a cluster so it's created from the cluster factory, (3) the kubeconfig path may be in the `KUBECONFIG` environment variable or (4) we can use the default kubeconfig from `~/.kube/config`. So, to get the configuration from any of these ways or sources, in that particular order, we will use loading rules and the default values:

```go
func (f *factory) ToRawKubeConfigLoader() clientcmd.ClientConfig {
	loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
	loadingRules.DefaultClientConfig = &clientcmd.DefaultClientConfig
  loadingRules.ExplicitPath = f.KubeConfig
  configOverrides := &clientcmd.ConfigOverrides{
		ClusterDefaults: clientcmd.ClusterDefaults,
    CurrentContext:  f.Context,
  }

  return clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, configOverrides)
}
```

From this `ClientConfig` we can generate the REST Config, the same config from the initial version that was used to create the Clientset:

```go
func (f *factory) ToRESTConfig() (*rest.Config, error) {
  config, _ := f.ToRawKubeConfigLoader().ClientConfig()
  rest.SetKubernetesDefaults(config)
  return config, nil
}
```

By implementing these two methods and the methods `ToDiscoveryClient()` and `ToRESTMapper()` (check the code in the repository) we ensure `factory` implements the interface `genericclioptions.RESTClientGetter`. Most of the methods we use require the `RESTClientGetter` interface directly or indirectly.

One of the most important methods in Config is  `NewBuilder()`, which returns a `resource.Builder` that is used to read unstructured resources from different sources (filename, URL, io.Reader or `[]byte`).  The input may contain more than one resource in a file.

We get a Builder with the method `resource.NewBuilder()` and it requires a `RESTClientGetter`. Do you see now why it's important to implement this interface.

```go
func (f *factory) NewBuilder() *resource.Builder {
  return resource.NewBuilder(f)
}
```

The `Factory` interface is also a `RESTClientGetter` interface and some of the `Factory` methods are required by the client. These methods are: `DynamicClient()`, `KubernetesClientSet()`, `RESTClient()`, `NewBuilder()`, `ClientForMapping()` and others. Check the code in the repository to know how they look like.

### (2) Create the Client

The Client has the Factory and it implements the interface `RESTClientGetter` and the `Factory` interface. So, the Client has all we need to have a good Kubernetes client.

The client also store some important information used along the way such as the namespace, and the Kubernetes Clientset (the one we create in the initial version).

```go
type Client struct {
  Clientset        *kubernetes.Clientset
	factory          *factory
  namespace        string
  enforceNamespace bool
}
```

In the client we have some helpers to return the `Result` from the `Builder`. Basically to get the Result we need a chain of methods like the following:

```go
result := c.factory.
  NewBuilder().
  Unstructured().                                       // Only if required
  Schema(validation.NullSchema{}).											// Do not validate the code
  ContinueOnError().
  NamespaceParam(c.namespace).
  DefaultNamespace().
  FilenameParam(c.enforceNamespace, filenameOptions).  // If the input are files or URLs
  Stream(r, "").                                       // If the input is a io.Reader
  Flatten().
  Do()
```

As the methods `Unstructured()`, `FilenameParam()` and `Stream()` are not always in the chain and depend of the needs, we have the following helpers: `ResultForFilenameParam()` and `ResultForReader()`.

```go
func (c *Client) ResultForReader(r io.Reader, unstructured bool) *resource.Result {
  b := c.factory.NewBuilder()
	if opt.Unstructured {
		b = b.Unstructured()
	}

  return b.
    Stream(r, "").
    Flatten().
    Do()
}

func (c *Client) ResultForFilenameParam(filenames []string, unstructured bool) *resource.Result {
	filenameOptions := &resource.FilenameOptions{
		Recursive: false,
		Filenames: filenames,
	}
  
  b := c.factory.NewBuilder()
	if unstructured {
		b = b.Unstructured()
	}

	return b.
    FilenameParam(f.enforceNamespace, filenameOptions).
		Flatten().
		Do()
}
```

### (3) Create, Update or Delete known resources using the API data structures

Not all the resources we are going to create are of unknown type, for example the Namespaces, so with the following code we accomplish that:

```go
func NewClientE(context, kubeconfig string) (*Client, error) {
  factory := newFactory(context, kubeconfig)
  ...
  client.Clientset = factory.KubernetesClientSet()
  ...
  return client, nil
}

func (c *Client) CreateNamespace(namespace string) error {
  ns := &v1.Namespace{
    ObjectMeta: metav1.ObjectMeta{
      Name: namespace,
      Labels: map[string]string{
        "name": namespace,
      },
    },
  }
  _, err := c.Clientset.CoreV1().Namespaces().Create(ns)
  return err
}

func (c *Client) DeleteNamespace(namespace string) error {
	return c.Clientset.CoreV1().Namespaces().Delete(namespace, &metav1.DeleteOptions{})
}
```

### (4) Create or Update the resources of unknown type

And finally, to create the resources or update the existing ones, we have the `Apply()` method.

```go
func (c *Client) Apply(content []byte) error {
  r := c.ResultForContent(content, true)
  return r.Visit(func(info *resource.Info, err error) error {
    if err != nil {
      return err
    }
    current, err := resource.NewHelper(info.Client, info.Mapping).Get(info.Namespace, info.Name, info.Export)
		if err != nil {
			if !errors.IsNotFound(err) {
				return err
			}
			return create(info, nil)
		}
		return patch(info, current)
  })
}
```

After getting the `Result` from the Builder which takes the content of the resource (either from a file or Go template). The Result has the method `Visit()` with a function as unique parameter to walk through all the resources identified, each identified resource is in the variable `info` of `resource.Info` type.

The function checks if the resource exists with the method `Get()` from the helper, there may be different kind of errors but the one we care about is `errors.IsNotFound(err)`. If the error is because the resource is not found, then create it. Otherwise, if there was no error at all, patch it.

To create the resource we get assistance from the helper method from `resource` to create the HTTP request and get the final resource object which is used to update the resource in the `info` variable.

```go
func create(info *resource.Info) error {
  options := metav1.CreateOptions{}
  obj, err := resource.NewHelper(info.Client, info.Mapping).Create(info.Namespace, true, info.Object, &options)
  if err != nil {
    return fmt.Errorf("creating %s. %s", info.String(), err)
  }
  info.Refresh(obj, true)
  return nil
}
```

The patching is more complicated. The patching is done with the `Patch` method of the resource helper, it requires a patch which is a slices of bytes `[]byte`.  To get this patch we use `strategicpatch.CreateThreeWayMergePatch()` passing the current object in the cluster, the new object required by the user and the last applied version of such object obtained from the object annotations, all of them in JSON. This patching method is called (as the func name states) [3-way-merge patch](https://en.wikipedia.org/wiki/Merge_(version_control)#Three-way_merge) and requires the patch type `types.StrategicMergePatchType`. To view this code, check the `patch.go` file from the repository. 

Since Kubernetes 1.16 the [Service Side Patch](https://en.wikipedia.org/wiki/Merge_(version_control)#Three-way_merge) feature is in beta and if your cluster supports it, you basically needs the new object required by the user ni JSON and use the patch type `types.ApplyPatchType`. Then call the same `Patch` method of the resource helper.

```go
func serverSideApply(info *resource.Info, err error) error {
	data, err := runtime.Encode(unstructured.UnstructuredJSONScheme, info.Object)
	if err != nil {
		return err
	}
	options := metav1.PatchOptions{
		Force:        true,
	}
	obj, err := resource.NewHelper(info.Client, info.Mapping).Patch(info.Namespace, info.Name, types.ApplyPatchType, data, &options)
	if err != nil {
		return err
	}
	info.Refresh(obj, true)
	return nil
}
```

Another patching method is `types.MergePatchType` which creates a 3-way-merge patch based on JSON merge patching. This one is used when the new object is not registered in the schema.

If any of these patches fails the last option is to delete the current object and create the new one. This may not be a good idea, so let the decision to the user/developer to do this by forcing the patching.

```go
...
  if err != nil && (errors.IsConflict(err) || errors.IsInvalid(err)) && force {
		patchBytes, patchObject, err = deleteAndCreate(info, patchBytes)
	}
...
```

To delete the object select the `DeletePropagationForeground` policy to delete the objects in cascade. If the creation of the object fails, restore the previous object.

```go
func deleteAndCreate(info *resource.Info, modified []byte) ([]byte, runtime.Object, error) {
	helper := resource.NewHelper(info.Client, info.Mapping)
  
  policy := metav1.DeletePropagationForeground
  delOptions := &metav1.DeleteOptions{
    PropagationPolicy: &policy
  }
  if _, err := helper.DeleteWithOptions(info.Namespace, info.Name, delOptions); err != nil {
		return nil, nil, err
	}

  ...

	options := metav1.CreateOptions{}
	createdObject, err := helper.Create(info.Namespace, true, info.Object, &options)
	if err != nil {
		recreated, recreateErr := helper.Create(info.Namespace, true, info.Object, &options)
		if recreateErr != nil {
			err = fmt.Errorf("An error occurred force-replacing the existing object with the newly provided one. %v.\n\nAdditionally, an error occurred attempting to restore the original object: %v", err, recreateErr)
		} else {
			createdObject = recreated
		}
	}
	return modified, createdObject, err
}

```

## Conclusion 

The `kubectl` CLI is great to control your Kubernetes cluster but not everything can be done with `kubectl` if you are developing in Go or other language.

The  Kubernetes API is a very well designed and implemented API but still complex for some actions. It is getting simpler and simpler over time. Anytime soon we wouldn't need any kind of module to interact with them. Meanwhile, if you don't want to use the oficial Go packages from Kubernetes, feel free to use the [klient](https://github.com/johandry/klient) Go package or the Helm (`helm.sh/helm/v3/pkg/kube`) Go package.

The [klient](https://github.com/johandry/klient) Go package is in use on production and will have more features to make it more appealing and useful to Go and Kubernetes application developers. If you'd like to contribute to it, please, open an issue or create a Pull Request. I'll appreciate your contribution.

