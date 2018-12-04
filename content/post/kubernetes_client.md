---
title: "Building a Kubernetes Client in Go"
date: 2018-12-01T11:56:02-08:00
draft: true
---

# Building a Kubernetes Client in Go

In front of me was another challenge: to build a kubernetes client in Go. It means, having an existing Kubernetes cluster it's required a program to create or update resources such as ConfigMaps and Deployments.

Initially I knew the resources to create, for example a ConfigMap, so no big deal, just use the Kubernetes clientset `kubernetes.Clientset` from `github.com/kubernetes/client-go` and there are plenty of examples like those in the [examples](https://github.com/kubernetes/client-go/tree/master/examples) directory from the same package. Here is a simple example to create a ConfigMap resource:

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

This code gets the same results as applying with `kubectl` the following ConfigMap file:

```yaml
apiVersion: v1
data:
  ui.properties: |
    color.good=purple
    color.bad=yellow
    allow.textmode=true
kind: ConfigMap
metadata:
  creationTimestamp: ...
  name: game-data
  namespace: game
  resourceVersion: ...
  selfLink: /api/v1/namespaces/game/configmaps/game-data
  uid: ...
```

If these are the requirements then problem solved. To create/update known resources you just need to:

1. Create the Config from the kubeconfig file
2. Create the Clientset from this config
3. Create the resource(s) using the appropriate API structure (i.e. `core/v1` and `meta/v1`)
4. Identify if the resource exists using `Get()` and the right resource method. If it exist, use `Create()`, otherwise use `Update()`

Simple, right? :slightly_smiling_face:

Unfortunately, the requirements changed (weird, they never change, right?) and now the resource are unknown and are provided to the client by a file, a Go template or a HTTP URL.

So, goodbye to the clientset and the awesome data structures from `k8s.io/api` (we'll see you later tho) and welcome to the vast collection of Kubernetes data structures and methods.

By the time I'm writing this post there is no much documentation about how to do this, so I had to dug into the deep code of Kubernetes and other tools to get ...

## A Kubernetes semi-client to apply resources of any type

In case you are in hurry and just want to read code, no problema, go to the github repository `johandry/kube-client`, everything is there and with more code because the code in this post has been simplified.

<u>Important</u>, I'm ignoring most of the errors in the code, **<u>don't do that</u>**, I just doing it to simplify the code and save space. Refer to the code in the repository to get the entire code and error handling.

The plan to get this done is almost similar to the steps above, so let's get started with the step #1:

### (1) Create the Config

Let's encapsulate all the configuration data such as the kubeconfig path and context into the `Config` struct.

```go
type Config struct {
  KubeConfig    string
  Context       string
}
```

Checking the code of `kubectl` and the `apply` command, they use a `Factory` interface and structure to provide the REST Configuration, a REST Mapper, a Discovery and REST Client, and a Builder among other things. The good news is, all these methods and what they provide can be obtained from the configuration.

The first and the foundation for all the other methods is the `ClientConfig`, to create it we will need (1) the path to the kubeconfig file and the context, but this is not the only way, (2) the program may be running in a cluster, (3) the kubeconfig path may be in the KUBECONFIG environment variable or (4) we can use the default kubeconfig from `~/.kube/config`. So, to get the configuration from any of these ways or sources, in that particular order, we will use loading rules and the default values:

```go
func (c *Config) ToRawKubeConfigLoader() clientcmd.ClientConfig {
  loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
  loadingRules.DefaultClientConfig = &clientcmd.DefaultClientConfig
  loadingRules.ExplicitPath = c.KubeConfig
  configOverrides := &clientcmd.ConfigOverrides{
    ClusterDefaults: clientcmd.ClusterDefaults,
    CurrentContext:  c.Context,
  }

  return clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, configOverrides)
}
```

From this `ClientConfig` we can generate the REST Config, the same config from the initial version that was used to create the Clientset:

```go
func (c *Config) ToRESTConfig() (*rest.Config, error) {
  config, _ := c.ToRawKubeConfigLoader().ClientConfig()
  rest.SetKubernetesDefaults(config)
  return config, nil
}
```

By implementing these two methods and the methods `ToDiscoveryClient()` and `ToRESTMapper()` (check the code in the repository) we ensure `Config` implements the interface `genericclioptions.RESTClientGetter`. Most of the methods we use require the `RESTClientGetter` interface directly or indirectly.

One of the most important methods in Config is  `NewBuilder()`, which returns a `resource.Builder` that is used to read unstructured resources from different sources (filename, URL, io.Reader or `[]byte`).  The input may contain more than one resource in a file.

We get a Builder with the method `resource.NewBuilder()` and it requires a `RESTClientGetter`. Do you see now why it's important to implement this interface.

```go
func (c *Config) NewBuilder() *resource.Builder {
  return resource.NewBuilder(c)
}
```

The `Factory` interface is also a `RESTClientGetter` interface and some of the `Factory` methods are required by the client. These methods are: `DynamicClient()`, `KubernetesClientSet()`, `RESTClient()`, `NewBuilder()`, `ClientForMapping()` and others, but not all these methods are required at this time for a simple client.

### (2) Create the Client

The Client has the Config and it implements the interface `RESTClientGetter` and (partially) `Factory`. So, the Client have all we need to have a good Kubernetes client.

The client also store some important information used along the way such as the namespace, and the Kubernetes Clientset (the one we create in the initial version).

```go
type Client struct {
  Config           *Config
  namespace        string
  enforceNamespace bool
  clientset        *kubernetes.Clientset
}
```

In the client we have some helpers to return the `Result` from the `Builder`. Basically to get the Result we need a chain of methods like the following:

```go
r := c.Config.
  NewBuilder().
  Unstructured().                                       // Only if required
  Schema(c.validator).
  ContinueOnError().
  NamespaceParam(c.namespace).
  DefaultNamespace().
  FilenameParam(c.enforceNamespace, filenameOptions).  // If the input are files or URLs
  Stream(r, "").                                       // If the input is a io.Reader
  Flatten().
  Do()
```

As the methods `Unstructured()`, `FilenameParam()` and `Stream()` are not always in the chain and depend of the needs, we have the following helpers: `UnstructuredBuilder()`, `Builder()`, `ResultForFilenameParam()` and `ResultForReader()`.

```go
func (c *Client) ResultForReader(r io.Reader, unstructured bool) *resource.Result {
  var b *resource.Builder
  if unstructured {
    b = c.UnstructuredBuilder()
  } else {
    b = c.Builder()
  }

  return b.
    Stream(r, "").
    Flatten().
    Do()
}

func (c *Client) ResultForContent(content []byte, unstructured bool) *resource.Result {
  b := bytes.NewBuffer(content)
  return c.ResultForReader(b, unstructured)
}
```

### (3) Create static resources using the API data structures

Not all the resources we are going to create are of unknown type, one of them is the Namespace where the given resource will be created. We have to ensure that Namespace is there, so with the following code we accomplish that:

```go
func NewClientE(context, kubeconfig string) (*Client, error) {
  config := NewConfig(context, kubeconfig)
  ...
  clientset, _ := config.KubernetesClientSet()
  client.clientset = clientset
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
  _, err := c.clientset.CoreV1().Namespaces().Create(ns)
  return err
}

func (c *Client) Namespace(namespace string) (*v1.Namespace, error) {
  return c.clientset.CoreV1().Namespaces().Get(namespace, metav1.GetOptions{})
}

func (c *Client) ApplyNamespace(namespace string) error {
  _, err := c.Namespace(namespace)
  if err != nil && errors.IsNotFound(err) {
    if err := c.CreateNamespace(namespace); errors.IsAlreadyExists(err) {
      return nil
    }
  }
  return err
}
```

### (4) Create or Update the resources of unknown type

And finally, to create the resources or update the existing ones, we have the `Apply()` method.

```go
func (c *Client) Apply(content []byte) error {
  if err := c.ApplyNamespace(c.namespace); err != nil {
    return err
  }
  r := c.ResultForContent(content, true)
  err := r.Visit(func(info *resource.Info, err error) error {
    if err != nil {
      return err
    }
    if err := info.Get(); err != nil {
      if !errors.IsNotFound(err) {
        return fmt.Errorf("retrieving current configuration of %s. %s", info.String(), err)
      }
      return create(info)
    }
    return patch(info)
  })

  return err
}
```

After ensure the client namespace is there we get the `Result` from the Builder which takes the content of the resource (either from a file or Go template). The result have the method `Visit()` with a function as unique parameter. `Visit()` uses this function to walk over all the resources identified, each identified resource is in the variable `info` of `resource.Info` type.

The function checks if the resource exists with the method `Get()`, there may be different kind of errors but the one we cares about is `errors.IsNotFound(err)`. If the error is because the resource was not found, then creates it. Otherwise, if there was no error at all, then patch it.

The creation is as follows:

```go
func create(info *resource.Info) error {
  options := metav1.CreateOptions{}
  obj, err := resource.NewHelper(info.Client, info.Mapping).Create(info.Namespace, true, info.Object, &options)
  if err != nil {
    return fmt.Errorf("creating %s. %s", info.String(), err)
  }
  return info.Refresh(obj, true)
}
```

To create it we get assistance from the helper method from `resource` to create the HTTP request and get the final resource object which is used to update the resource in the `info` variable.

The patching is as follow: