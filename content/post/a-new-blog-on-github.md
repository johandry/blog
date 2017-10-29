---
title: "A New Blog on Github"
date: 2017-10-28T23:42:14-07:00
draft: true
tags: ["Hugo", "Blogging"]
---

Here is everything I did to create this blog with Hugo and publish it on GitHub. I don't have to do it again but may help others to do the same.

You'll need Hugo and Git. Once you have Hugo, create the blog with:

```
brew install hugo
hugo new site blog
cd blog
git init
```

The next step is to choose a theme, which took me a long time. Go to [https://themes.gohugo.io/](https://themes.gohugo.io/), make sure to browse the demo of the preferred themes. In my case I choose [Blackburn](https://themes.gohugo.io/blackburn/). Get the theme with:

    cd themes
    git clone https://github.com/yoshiharuyamashita/blackburn.git

Open `config.toml` and copy the content from the theme repository. Edit or add the following variables:

* **title**
* **author**
* **theme**
* **subtitle**
* **brand**
* **googleAnalytics**
* **disqus**
* **highlightjs**
* **highlightjs_extra_languages**

Example:

{{<highlight toml>}}
title = "Johandry's Blog"
author = "Johandry Amador"
theme = "blackburn"

[params]
  subtitle = "Things & Stuffs about DevOps and Go"
  brand = "Johandry"
  disqus = "johandry"
  highlightjs = "vs2015"
  highlightjs_extra_languages = ["yaml", "bash", "dockerfile", "go", "json", "makefile", "shell"]
{{</highlight>}}

Modify, if you need it, the links or content in the `[menu]` section and add the username or ID in the `[social]` section or delete those you don't have.

You are ready for the first post!

    hugo new post/first-post.md

Open the file `post/first-post.md` to add your first content.

Use `hugo` to see how it looks:

    hugo server -D

Now open in a browser [http://localhost:1313](http://localhost:1313).

When you are happy with the content, make sure to remove the metadata `draft`. Otherwise it won't be considered by hugo when regenerate the site. Also, include the tags or topics using the metadata `tags` and `topics`, like this:

{{<highlight yaml>}}
---
title: "A New Blog on Github"
date: 2017-10-28T23:42:14-07:00
tags: ["Hugo", "Blogging"]
---
{{</highlight>}}

From the 3 options to publish the blog on GitHub I opt for the [gh-pages branch](https://gohugo.io/hosting-and-deployment/hosting-on-github/#deployment-from-your-gh-pages-branch) option. And this is what I did:

Create a GitHub repository named `blog`, very original, right?

    # Ignore public/ in the master branch:
    echo "public" >> .gitignore

    # Initialize the master branch:
    git add .
    git commit -m "First commit"
    git remote add origin https://github.com/johandry/blog.git
    git push origin master

    # Initialize branch gh-pages as an empty orphan branch:
    git checkout --orphan gh-pages
    git reset --hard
    git commit --allow-empty -m "Initializing gh-pages branch"
    git push origin gh-pages
    git checkout master

    # Check out the gh-pages branch into the public/ folder:
    rm -rf public
    git worktree add -B gh-pages public origin/gh-pages

Go to the DNS service and create a subdomain named `blog` configured as an alias for the CNAME of my github page, which is `johandry.github.io`. In my repository I also have the project `johandry.github.io` so it's required to create the file `static/CNAME` with the domain name.

    echo "blog.johandry.com" > static/CNAME

Go to **Settings** → **GitHub Pages** in the blog repository. Make sure **Source** is set to `gh-pages branch` and enter the domain name in **Custom Domain** (i.e. `blog.johandry.com`).

Open `config.toml` again and update the `baseURL` variable to the base URL using the domain name: `baseURL = "http://blog.johandry.com/"`.

Regenerate the blog, commit and push it:

    hugo

    cd public
    git add .
    git commit -m "Publishing to gh-pages"
    cd ..

    git push origin gh-pages

You may have to wait a few minutes for the domain name to be replicated, then go to `http://blog.johandry.com` to test your new blog.

## Sources

* Hugo Quick Start: https://gohugo.io/getting-started/quick-start/
* Blackburn Repository: https://github.com/yoshiharuyamashita/blackburn
* GitHub Custom Domains: https://help.github.com/articles/using-a-custom-domain-with-github-pages/
* Hugo Docs to Host on GitHub: https://gohugo.io/hosting-and-deployment/hosting-on-github/
