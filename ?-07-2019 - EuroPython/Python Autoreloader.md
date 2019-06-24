theme: zurich, 1
slidenumbers: true
footer: Tom Forbes - EuroPython 2019

# Writing an autoreloader in Python

## EuroPython 2019

### Tom Forbes - tom@tomforb.es

---

![inline](./images/onfido.png)

# [fit] https://onfido.com/careers

---

## 1. What is an autoreloader?

## 2. Django's implementation

## 3. Rebuilding it

## 4. The aftermath

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

`reload()` does nothing but re-imports the module

Yes, this is "hot reloading", but is entirely useless for writing an autoreloader.

---

# State is the enemy of an autoreloader

## Python objects have *lots* of state

^ All hot reloaders utilize language features that minimize state.

---

#[fit] Imagine you wrote a hot-reloader for Python

You import a function from a module:

`from module import a_function`

Then you delete `a_function` from `module.py`

After reloading `module`, what does `a_function` reference?

^ If it references old code, you have not reloaded properly. 

^ You could find all modules that reference `a_function` and reload them as well, cascading.

^ The point here is that it's almost impossible to do this in Python in the general case. For specific, limited 
cases it works, but when you are talking about a large application you want to ensure that reloading works correctly, 
else you will end up with bugs that only appear after specific reloads! Not good!

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

---


# The history of the Django autoreloader

First commit in 2005

No major changes until 2013 when `inotify` support was added

`kqueue` support was also added in 2013, then removed 1 month later

---

[.build-lists: true]

# Summary so far:

1. An autoreloader is a common development tool

2. Hot reloading is really difficult

3. Python autoreloaders restart the process on code changes

4. The Django autoreloader was pretty crufty

---

# (Re-)Building an autoreloader

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

Sometimes things that are *not* modules find their way inside `sys.modules`

```
❯ ipython -c 'import sys; print(sys.modules["typing.io"])'
<class 'typing.io'>
```

---

# Python's imports are very dynamic

The import system is unbelievably flexible

[https://github.com/nvbn/import\_from\_github\_com](https://github.com/nvbn/import_from_github_com)

```python
from github_com.kennethreitz import requests
```

^ 60 lines of code!

^ Other more common uses: pytest, Cython

Can import from `.zip` files, or from `.pyc` files directly

^ Two different modules can share the same file, or have no file at all.

---

# What can you do?

![inline](images/shrug.jpg)

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
os.stat('/etc/password').st_mtime
```

^ The last modification time can mean different things to different OS's and platforms. 

[^1]: Except when they don't

---

# Filesystems can be _weird_.

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

^ current time within the Linux kernel is cached. Typically it's updated around 10ms.

---

# Filesystems can be _weird_.

Network filesystems mess things up completely

^ The clocks may be out of sync, modifications on the server may modify the mtime in random ways

`os.stat()` suddenly becomes expensive!

^ Network filesystems may be very slow: a `stat()` call might require network access!

---

# Watching files: A simple implementation

```python
import time, os

def watch_files():
    file_times = {} # Maps paths to last modified times
    while True:
        for path in get_files_to_watch():
            mtime = os.stat(path).st_mtime
            previous_mtime = file_times.setdefault(path, mtime)
            if mtime > previous_mtime:
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
| Tornado | 2 :scream: |
| Werkzeug (Flask) | 3 |
| Pyramid | 6 |

^ Mostly these are high level integration tests. Obviously these all work quite well, and my point here is not shame 
  these projects, but clearly this is a hard thing to test.

---

# Making it testable

Reloaders are infinite loops that run in threads and rely on a big ball of external state.

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

---

# Generators!

```python
def test_it_works(tmp_path):
    reloader = watch_files(sleep_time=0.001)
    next(reloader)  # Initial tick
    increment_file_mtime(tmp_path)
    next(reloader)
    assert reloader_has_triggered
```

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

^ `sys.modules` does change at runtime, but not *that* often. In the real world we need a non-trivial amount of 
  processing to iterate and check each module. We can use `lru_cache` to skip needlessly re-processing the modules list.

---

# Making it efficient: Iterating modules

^ The standard library has lots of modules.

^ Can we skip watching them?

^ This is harder than it sounds!

---

# Making it efficient: Iterating modules

```python
import site
site.getsitepackages()
```

Not available in a virtualenv :scream:

---

# Making it efficient: Iterating modules

```python
import distutils.sysconfig
print(distutils.sysconfig.get_python_lib())
```

Works, but some systems (Debian) have more than one site package directory

---

# Making it efficient: Iterating modules

![inline](./images/risk-reward.jpg)

^ It might not be safe to do this in all cases, and if a mistake is made then that will frustrate users. Also no other
  autoreloader I could find does this.

---

# Making it efficient: Filesystem notifications

^ polling is evil. OS's have built in support for filesystem notifications. This is where you tell the OS to tell *you* 
  when a file is changed, immediately. Sounds good, right?

---

# Making it efficient: Filesystem notifications

![inline](./images/highway-to-hell.jpg)

^ This is the highway to hell.

---

# Making it efficient: Filesystem notifications

^ Each platform has hugely different ways of handling this, each with their own quirks

^ Notifiers are potentially expensive

^ Designed for longer-term monitoring. 

^ In our model we would create and destroy them quickly.

![inline](./images/watchman.png)

https://facebook.github.io/watchman/

^ Watchman is a daemon that handles this all for you.

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

---

# The aftermath

:heavy_check_mark: Much more modern, easy to extend code

:heavy_check_mark: Faster, and can use Watchman if available

:heavy_check_mark: 72 tests :tada:

:heavy_check_mark: No longer a "dark part" of Django

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

# Questions?

### Tom Forbes - tom@tomforb.es