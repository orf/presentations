theme: zurich, 1
slidenumbers: true
footer: Tom Forbes - EuroPython 2019

# Writing an autoreloader in Python

## EuroPython 2019

### Tom Forbes - tom@tomforb.es

---

## 1. What is an autoreloader?

## 2. Django's implementation

## 3. Rebuilding it

## 4. The aftermath

^ The basis of this talk is a contribution that I made to Django, where I "improved" the old 
autoreloader. The contents and the theory will be generic, but I will talk about the risks of writing your 
own autoreloader in the context of Django.

---

# [fit] What is an autoreloader?

A component in a larger system that detects changes to your source code and applies them, without developer interaction.

^ Example: Refreshing your browser tab when you change a HTML or JavaScript file

^ I find them interesting: they are very common, in the case of Django and other frameworks they a critical part of the
 framework - as you will find out later if they go wrong people get upset, they are very language specific and there
 is no general solution, and I think they are not that well understood. People just expect them to work.

---

# Hot reloading

A special type of autoreloader that reloads your changes without restarting the system.

^ The "holy grail" of autoreloaders.

^ Example: Changing the stylesheet of a web page. No refreshing required, the browser can apply the changes without 
needing a full reload.

Shout out to Erlang where this is a **deployment strategy**.

---

# But Python has `reload()`?

```python
import time
import my_custom_module

while True:
    time.sleep(1)
    reload(my_custom_module)
```

`reload()` does nothing but re-imports the module

Yes, this is "hot reloading", but is entirely useless for writing an autoreloader.

---

# State is the enemy of an autoreloader

## Python objects have *lots* of state

^ All hot reloaders utilize language features that minimize state.

^ Example: React has a hot reloader that leverages how React manages state - you can replace a component in a page.
  So does Erlang.

---

#[fit] Imagine you wrote a hot-reloader for Python

You import a function in `module_a` from `module_b`:

`from module_b import some_function`

Then you delete `some_function` from `module_b.py`

After reloading `module_b`, what does `module_a.some_function` reference?

^ If it references old code, you have not reloaded properly. 

^ You could find all modules that reference `a_function` and reload them as well, cascading.

^ The point here is that it's almost impossible to do this in Python in the general case. For specific, limited 
cases it works (ipython has one), but when you are talking about a large application you want to ensure that reloading
works correctly, else you will end up with bugs that only appear after specific reloads! Not good!

---

# [fit] So how do we reload code in Python?

![inline](./images/on-off.jpg)

---

# We restart the process.

# On every code change.

# Over and over again.

^ Kind of like refreshing a browser window.

---

[.build-lists: true]

# [fit] When you run `manage.py runserver`:

1. Django re-executes `manage.py runserver` with a specific  environment variable set

2. The child process runs Django, and watches for any file changes

3. When a change is detected it exits with a specific exit code (3)

4. Django restarts it.

^ So it's a simple loop: You have a process that's a supervisor, and it will restart the child process when it exits 
with a specific error code. This is the most common, and simplest, form of an autoreloader.

---


# The history of the Django autoreloader

First commit in 2005

No major changes until 2013 when `inotify` support was added

`kqueue` support was also added in 2013, then removed 1 month later

^ Django code is generally quite high quality, with a lot of emphasis on testing and readability (in most parts). 
The autoreloader module stood out to me as one of the least touched, and most crufty parts of Django. The code was old, 
not idiomatic and hard to extend. It seemed to me to be append-only code. 

---

[.build-lists: true]

# Summary so far:

1. An autoreloader is a common development tool

2. Hot reloading is really difficult due to messy state

3. Python autoreloaders restart the process on code changes

4. The Django autoreloader was old and hard to extend

---

# (Re-)Building an autoreloader

[.build-lists: true]

Three or four steps:

1. Find files to monitor

2. Wait for changes and trigger a reload

3. Make it testable

4. Bonus points: Make it efficient

---

# Finding files to monitor

`sys.modules`, `sys.path`, `sys.meta_path`

```
❯ ipython -c 'import sys; print(len(sys.modules))'
642
```

^ sys.modules contains all the Python modules currently loaded, mapped to their names.
sys.path is where Python can find modules to import. 

^ As you can see, there are lots of modules. When you run `ipython` we have nearly 650 modules loaded.

```
❯ python -c 'import sys; print(len(sys.modules))'
42
```

---

# Finding files to monitor

Sometimes things that are *not* modules find their way inside `sys.modules`

```
❯ ipython -c 'import sys; print(sys.modules["typing.io"])'
<class 'typing.io'>
```

^ I don't know why, or how, this ends up here, but it's quite annoying as you sort of expect `sys.modules` to contain 
only modules.

^ sys.modules can be mutated by Python code.

---

# Python's imports are very dynamic

The import system is unbelievably flexible

[https://github.com/nvbn/import\_from\_github\_com](https://github.com/nvbn/import_from_github_com)

```python
from github_com.kennethreitz import requests
```

^ 60 lines of code!

^ sys.meta_path can contain arbitrary things written in Python

^ Other more common uses: pytest, Cython

Can import from `.zip` files, or from `.pyc` files directly

^ Two different modules can share the same file, or have no file at all.

^ There isn't always a mapping between a module and an actual, unique file.

---

# What can you do?

![inline](images/shrug.jpg)

^ So what can we do if someone wants to import code directly from Github?

^ So the point here is: Python imports are very dynamic, not everything has an actual file, so not all changes 
can be detected.

---

# Finding files: The simplest implementation

```python
import sys

def get_files_to_watch():
    return [
        module.__spec__.origin
        for module in sys.modules.values()
    ]
```

^ Each module has a `__spec__`, and that object has an `origin`. Lots of exclusions to this, like I said before.

---

# (Re-)Building an autoreloader

Three or four steps:

1. ~~Find files to monitor~~

2. Wait for changes and trigger a reload

3. Make it testable

4. Bonus points: Make it efficient

---

# Waiting for changes

All[^1] filesystems report the last modification of a file

```python
mtime = os.stat('/etc/password').st_mtime
print(mtime)
1561338330.0561554

print(time.time() - mtime)
155299.3184275627
```

^ 155 thousand seconds ago, or 1.7 days ago

^ The last modification time can mean different things to different OS's and platforms.

[^1]: Except when they don't

---

# Filesystems can be _weird_.

^ current time within the Linux kernel is cached. Typically it's updated around 10ms.

^ Python does a great job at abstracting most platform-specific things away. You cannot really escape from the realities 
  of the filesystem though. Case in point: macOS has a case-insensitive filesystem by default.
  
HFS+: 1 second time resolution

Windows: 100ms (files may appear in the past :scream:)

Linux: Depends on your hardware clock!

```python
p = pathlib.Path('test')
p.touch()
time.sleep(0.005)  # 5 milliseconds
p.touch()
```

---

# Filesystems can be _weird_.

Network filesystems mess things up completely

^ The clocks may be out of sync, modifications on the server may modify the mtime in random ways

`os.stat()` suddenly becomes expensive!

^ Network filesystems may be very slow: a `stat()` call might require network access!

---

# Watching files: A simple implementation

[.code-highlight: all]
[.code-highlight: 4]
[.code-highlight: 5-6]
[.code-highlight: 7-8]
[.code-highlight: 9-11]

```python
import time, os

def watch_files():
    file_times = {} # Maps paths to last modified times
    while True:
        for path in get_files_to_watch():
            mtime = os.stat(path).st_mtime
            previous_mtime = file_times.setdefault(path, mtime)
            if mtime != previous_mtime:
                exit(3)  # Change detected!
        time.sleep(1)
```
---

# (Re-)Building an autoreloader

Three or four steps:

1. ~~Find files to monitor~~

2. ~~Wait for changes and trigger a reload~~

3. Make it testable

4. Bonus points: Make it efficient

---

# Making it testable

Not many tests for reloaders in the wider ecosystem

| Project | Test Count |
| --- | :---: |
| Tornado | 2 |
| Werkzeug (Flask) | 3 |
| Pyramid | 6 |

^ Mostly these are high level integration tests. They spawn a server, change a file and check if the server exited.

^ Obviously these all work quite well, and my point here is not shame 
  these projects, but clearly this is a hard thing to test.

---

# Making it testable

Reloaders are infinite loops that run in threads and rely on a big ball of external state.

^ Each of these things is hard to test by themselves, but when you combine them it gets even harder.

^ How do we make these testable?

---

# Generators!

^ A generator lets you suspend and resume execution

---

# Generators!

[.code-highlight: all]
[.code-highlight: 1, 9-10]

```python
def watch_files(sleep_time=1):
    file_times = {}
    while True:
        for path in get_files_to_watch():
            mtime = os.stat(path).st_mtime
            previous_mtime = file_times.setdefault(path, mtime)
            if mtime > previous_mtime:
                exit(3)
        time.sleep(sleep_time)
        yield
```

^ We have the sleep time as a parameter, and yield after we sleep.

---

# Generators!

[.code-highlight: all]
[.code-highlight: 2-3]
[.code-highlight: 4]
[.code-highlight: 5]
[.code-highlight: 6-7]

```python
def test_it_works(tmp_path):
    reloader = watch_files(sleep_time=0)
    next(reloader)  # Initial tick
    increment_file_mtime(tmp_path)
    next(reloader)
    assert reloader_has_triggered
```

^ You can test this with symbolic links, permission errors, files being intermittently available

---

# (Re-)Building an autoreloader

Three or four steps:

1. ~~Find files to monitor~~

2. ~~Wait for changes and trigger a reload~~

3. ~~Make it testable~~

4. Bonus points: Make it efficient

---

# Making it efficient

Slow parts: 

1. Iterating modules

2. Checking for file modifications

---

# Making it efficient: Iterating modules

[.code-highlight: all]
[.code-highlight: 3-4]
[.code-highlight: 6-8]

```python
import sys, functools

def get_files_to_watch():
    return sys_modules_files(sys.modules.values())

@functools.lru_cache(maxsize=1)
def sys_modules_files(modules):
    return [module.__spec__.origin for module in modules]
```

^ `sys.modules` does change at runtime, but not *that* often. Once the app has booted there are not that many modifications.

^ In the real world we need a non-trivial amount of processing . and we are checking for changes every 1 second, this adds a fair bit of overhead, and there 
  could be a very large number of modules. The old reloader took more time iterating sys.modules than it did stating the file.
  
^ We can use `lru_cache` to skip needlessly re-processing the modules list.

---

```python
def iter_modules_and_files(modules, extra_files):
    """Iterate through all modules needed to be watched."""
    sys_file_paths = []
    for module in modules:
        # During debugging (with PyDev) the 'typing.io' and 'typing.re' objects
        # are added to sys.modules, however they are types not modules and so
        # cause issues here.
        if not isinstance(module, ModuleType):
            continue
        if module.__name__ == '__main__':
            # __main__ (usually manage.py) doesn't always have a __spec__ set.
            # Handle this by falling back to using __file__, resolved below.
            # See https://docs.python.org/reference/import.html#main-spec
            # __file__ may not exists, e.g. when running ipdb debugger.
            if hasattr(module, '__file__'):
                sys_file_paths.append(module.__file__)
            continue
        if getattr(module, '__spec__', None) is None:
            continue
        spec = module.__spec__
        # Modules could be loaded from places without a concrete location. If
        # this is the case, skip them.
        if spec.has_location:
            origin = spec.loader.archive if isinstance(spec.loader, zipimporter) else spec.origin
            sys_file_paths.append(origin)

    results = set()
    for filename in itertools.chain(sys_file_paths, extra_files):
        if not filename:
            continue
        path = pathlib.Path(filename)
        try:
            resolved_path = path.resolve(strict=True).absolute()
        except FileNotFoundError:
            # The module could have been removed, don't fail loudly if this
            # is the case.
            continue
        results.add(resolved_path)
    return frozenset(results)
```
---

# Making it efficient: Skipping the stdlib

^ The standard library has lots of modules.

^ Can we skip watching them?

^ This is harder than it sounds!

^ So how do we know where the standard library is?

---

# Making it efficient: Skipping the stdlib

```python
import site
site.getsitepackages()
```

Not available in a virtualenv :scream:

^ Google it: Stack overflow with 20 answers: 
https://stackoverflow.com/questions/122327/how-do-i-find-the-location-of-my-python-site-packages-directory

---

# Making it efficient: Skipping the stdlib

```python
import distutils.sysconfig
print(distutils.sysconfig.get_python_lib())
```

Works, but some systems (Debian) have more than one site package directory.

^ I asked in the Python IRC channel, and someone pointed me to a bit of code that I could no longer find in a popular 
project (I think it was coverage), which used 5 or 6 different ways to detect the stdlib, falling back to hackily 
checking the path for the string 'site-packages'.

---

# Making it efficient: Skipping the stdlib

It all boils down to:

#[fit] Risk vs Reward

^ It might not be safe to do this in all cases, and if a mistake is made then that will frustrate users. Also no other
  autoreloader I could find does this.

---

# Making it efficient: Filesystem notifications

^ polling is evil. OS's have built in support for filesystem notifications. This is where you tell the OS to tell *you* 
  when a file is changed, immediately. Sounds good, right?

---

# Making it efficient: Filesystem notifications

Each platform has different ways of handling this, each with their own quirks

Watchdog[^1] implements 5 different ways - 3,000 lines of Python code.

^ Notifiers are potentially expensive and designed for longer-term monitoring. 

^ In our model we would create and destroy them quickly.

They are all *directory* based.

^ You watch a *directory* for changes, not a file. This makes the implementation 
a fair bit more complex.


[^1]: https://github.com/gorakhargosh/watchdog/tree/master/src/watchdog/observers

---

# Making it efficient: Filesystem notifications

![inline](./images/watchman.png)

https://facebook.github.io/watchman/

^ Watchman is a daemon that handles this all for you.

^ runs in background, you register watches with it, and it handles the nitty gritty.

---

# Making it efficient: Filesystem notifications

[.code-highlight: all]
[.code-highlight: 4-6]
[.code-highlight: 8-10]

```python
import pywatchman

def watch_files(sleep_time=1):
    client = pywatchman.client()
    for path in get_files_to_watch():
        client.watch_file(path)
    while True:
        changes = client.wait(timeout=sleep_time)
        if changes:
            exit(3)
        yield
```

^ Adding support for this was actually the reason I started working on refactoring the autoreloader in the first place.

---

# The aftermath

:heavy_check_mark: Much more modern, easy to extend code

:heavy_check_mark: Faster, and can use Watchman if available

:heavy_check_mark: 72 tests :tada:

:heavy_check_mark: No longer a "dark part" of Django

^ So all good, right? I'm a genius and it worked first time, everyone is happy?

---

# The aftermath

![inline](./images/bugs/1.png)

![inline](./images/bugs/2.png)

---

# The aftermath

![inline](./images/bugs/3.png)

![inline](./images/bugs/4.png)

---

# The aftermath

![inline](./images/bugs/5.png)

![inline](./images/bugs/6.png)

---

# The aftermath

![inline](./images/bugs/7.png)

^ My favorite issue. It didn't work on Windows.

^ I wanted to make a point about this as it shows the strange behavior and quirks you can run into while writing an 
autoreloader.

---

# The aftermath

[.code-highlight: all]
[.code-highlight: 2, 9]
[.code-highlight: 6]

```python
def watch_file():
    last_loop = time.time()
    while True:
        for path in get_files_to_watch():
            ...
            if previous_mtime is None and mtime > last_loop:
                exit(3)
        time.sleep(1)
        last_loop = time.time()
```

^ I wanted to detect new files that where added since the last iteration of the loop

---

# Conclusions:

## Don't write your own, use:

## https://github.com/Pylons/hupper

---

![inline](./images/onfido.png)

# [fit] https://onfido.com/careers

---

# Questions?

### Tom Forbes - tom@tomforb.es