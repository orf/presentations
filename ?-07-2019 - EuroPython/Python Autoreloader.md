theme: zurich
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

3. **Make it testable**

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

# Finding files: A simple implementation

```python
import sys, functools

def get_files_to_watch():
    return sys_modules_files(sys.modules.values())

@functools.lru_cache(maxsize=1)
def sys_modules_files(modules):
    return [module.__spec__.origin for module in modules]
```

---

# (Re-)Building an autoreloader

Three or four steps:

1. ~~Find files to monitor~~

2. Wait for changes and trigger a reload

3. **Make it testable**

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

3. **Make it testable**

4. Bonus points: Make it efficient

---

# Making a testable

Pretty hard to write tests for this kind of thing. Threading etc.

Flask (through Werkzeug): 4 or 5 tests. All integration.

Django (before rewrite): 2 direct reloading tests, 10 auxiliary ones

Pyramid (via hupper): 6 - Really nice library

---

# Making it testable


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

Use yield etc.

71 tests now in Django.

Examples of tests

---

# Making it efficient

Polling isn't great. How about native filesystem notifications?

Urgh. Hard. Use Watchman? Watchdog?

---

# The end result


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

Talk about why.

---

Windows can be even weirder

```python
def watch_file():
    last_loop = time.time()
    while True:
        for path in get_files_to_watch():
            ...
            if previous_mtime is None and mtime > last_loop:
                exit(3)
        last_loop = time.time()
```

^ I wanted to detect new files that where added since the last iteration of the loop