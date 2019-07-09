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

---

# [fit] What is an autoreloader?

A component in a larger system that detects and applies changes to source code, without developer interaction.

^ Example: automatically refreshing your browser tab when you change a HTML or JavaScript file

^ I find them interesting: they are very common.

^ A critical part of the framework.

^ not well understood. 

^ very language specific

^ The basis of this talk is what I learned while improving the Django implementation.

---

# Hot reloader

A special type of autoreloader that reloads your changes without restarting the system.

^ The "holy grail" of autoreloaders. Really fast and efficient.

^ Example: Changing the stylesheet of a web page. No refreshing required, the browser can apply the changes without 
needing a full reload.

Shout out to Erlang where you hot-reload code while deploying

^ These are impossible to write safely in Python *in the general case*.


---

# But Python has `reload()`?

```python
import time
import my_custom_module

while True:
    time.sleep(1)
    reload(my_custom_module)
```

^ `reload()` does nothing but re-imports the module

^ Yes, this is technically "hot reloading" a single module

^ You need a lot more before this is a *hot reloader*.

---

# Dependencies are the enemy of an autoreloader

## Python modules have *lots* of inter-dependencies

^ All hot reloaders utilize language or framework features that manage dependencies between things.

^ Erlang: everything uses message passing

^ CSS: no dependencies, can be safely re-applied

^ React: Components in a page can be easily replaced - that's how react works.

---

#[fit] Imagine you wrote a hot-reloader for Python

You import a function inside `your_module`:

`from another_module import some_function`

Then you delete `some_function` from `another_module.py`

After reloading, what does `your_module.some_function` reference?

^ If it references old code, you have not reloaded properly. 

^ You could find all modules that reference `a_function` and reload them as well, cascading.

^ It's impossible in the general case, for any given Python program.

^ For limited, smaller cases it may work - you can easily update a single reference to an object

^ Don't want to end up with bugs that only appear randomly in development!

---

# So how do we reload code in Python?

^ I'm glad you asked

---

# [fit] We turn it off and on again

![inline](./images/on-off.jpg)

---

# We restart the process.

# On every code change.

# Over and over again.

^ Kind of like refreshing a browser window.

^ You loose all state in the process, and it starts again from fresh

---

[.build-lists: true]

# [fit] When you run `manage.py runserver`:

1. Django re-executes `manage.py runserver` with a specific  environment variable set

2. The child process runs Django, and watches for any file changes

3. When a change is detected it exits with a specific exit code (3)

4. The parent Django process restarts it.

^ So it's a simple loop: You have a process that's a supervisor, and it will restart the child process when it exits

^ This is the most common, and simplest, form of an autoreloader.

---


# The history of the Django autoreloader

First commit in 2005

No major changes until 2013 when `inotify` support was added

`kqueue` support was also added in 2013, then removed 1 month later

^ Django code is generally quite high quality, with a lot of emphasis on testing and readability.

^ Old, crufty part of Django

^ The code was not idiomatic and hard to extend.

^ append-only code. 

^ Some new features would be very hard to add without refactoring.

---

[.build-lists: true]

# Summary so far:

1. An autoreloader is a common development tool

2. Hot reloaders are really hard to write in Python

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

`sys.modules`

```
❯ ipython -c 'import sys; print(len(sys.modules))'
642
```

^ sys.modules contains all the Python modules currently loaded, 

^ maps names to the modules

^ lots of modules. 

^ When you run `ipython` we have nearly 650 modules loaded.

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

^ You kind of expect sys.modules to contain only modules

^ sys.modules can be mutated by Python code.

^ Some libraries do crazy things!

---

# Python's imports are very dynamic

The import system is unbelievably flexible

Can import from `.zip` files, or from `.pyc` files directly

[https://github.com/nvbn/import\_from\_github\_com](https://github.com/nvbn/import_from_github_com)

```python
from github_com.kennethreitz import requests
```

^ 60 lines of code!

^ Can write a 'loader' to do magic things to imports

^ Other more common uses: pytest, Cython


^ Two different modules can share the same file, or have no file at all.

^ There isn't always a mapping between a module and an actual, unique file.

---

# What can you do?

![inline](images/shrug.jpg)

^ So what can we do if someone wants to import code directly from Github?

^ So the point here is: Python imports are very dynamic

^ not all changes can be detected.

^ we can try our best

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

^ All of these code samples are really simplistic - the Django implementation for this is over 40 lines long.

^ This is conceptually what we want to do.

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
```

^ We can use this to detect when a file has been changed

^ The last modification time can mean different things to different OS's and platforms.

[^1]: Except when they don't

---

# Filesystems can be _weird_.

^ current time within the Linux kernel is cached. Typically it's updated around 10ms.

^ Python does a great job at abstracting most platform-specific things away. 

^ You cannot really escape from the filesystem.

^ Case in point: macOS has a case-insensitive filesystem by default.
  
HFS+: 1 second time resolution

Windows: 100ms intervals (files may appear in the past :scream:)

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

^ Network filesystems may be very slow: a `stat()` call might require network access!

^ The clocks may be out of sync

`os.stat()` suddenly becomes expensive!

^ The time can be set by anything

^ It does not always mean there is a change

^ Reason for use: easy to implement, generally efficient and pretty good cross platform support

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

Not many tests in the wider ecosystem

| Project | Test Count |
| --- | :---: |
| Tornado | 2 |
| Flask | 3 |
| Pyramid | 6 |

^ Mostly these are high level integration tests. They spawn a server, change a file and check if the server exited.

^ Obviously these all work quite well

^ not shaming these projects

^ hard thing to test

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

^ add a sleep time parameter

^ add a yield

^ lets you write slightly better tests

---

# Generators!

[.code-highlight: all]
[.code-highlight: 2]
[.code-highlight: 3]
[.code-highlight: 4]
[.code-highlight: 5-6]


```python
def test_it_works(tmp_path):
    reloader = watch_files(sleep_time=0)
    next(reloader)  # Initial tick
    increment_file_mtime(tmp_path)
    with pytest.raises(SystemExit):
       next(reloader)
```

^ we have a way to pause our autoloader, make changes to the filesystem, and resume it.

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
    return sys_modules_files(frozenset(sys.modules.values()))

@functools.lru_cache(maxsize=1)
def sys_modules_files(modules):
    return [module.__spec__.origin for module in modules]
```

^ `sys.modules` doesn't often change after starting

^ In the real world we need a non-trivial amount of processing. 
  
^ We can use `lru_cache` to skip needlessly re-processing the modules list.

---

# Making it efficient: Skipping the stdlib + third party packages

^ The standard library has lots of modules.

^ Can we skip watching them?

^ This is harder than it sounds!

^ So how do we know where the standard library is?

---

# Making it efficient: Skipping the stdlib + third party packages

```python
import site
site.getsitepackages()
```

Not available in a virtualenv :scream:

^ Google it: Stack overflow with 20 different answers: 
https://stackoverflow.com/questions/122327/how-do-i-find-the-location-of-my-python-site-packages-directory

---

# Making it efficient: Skipping the stdlib + third party packages

```python
import distutils.sysconfig
print(distutils.sysconfig.get_python_lib())
```

Works, but some systems (Debian) have more than one site package directory.

^ Asked in IRC

^ Shown some code in a popular project (related to code coverage)

^ used 5 or 6 different ways to detect the stdlib

^ falling back to hackily checking the path for the string 'site-packages'.

---

# Making it efficient: Skipping the stdlib + third party packages

It all boils down to:

#[fit] Risk vs Reward

^ It might not be safe to do this in all cases.

^ and if a mistake is made then that will frustrate users. 

^ no other autoreloader I could find does this.

---

# Making it efficient: Filesystem notifications

^ calling stat repeatedly is wasteful. 

^ OS's have built in support for filesystem notifications.

^ The OS tells you when a change is made

---

# Making it efficient: Filesystem notifications

Each platform has different ways of handling this

Watchdog[^2] implements 5 different ways - 3,000 LOC!

^ Notifiers are potentially expensive

^ designed for longer-term monitoring. 

^ we create and destroy them quickly.

They are all *directory* based.

^ Directory based watching is complex

^ get all changes, including non python ones.


[^2]: https://github.com/gorakhargosh/watchdog/tree/master/src/watchdog/observers

---

# Making it efficient: Filesystem notifications

![inline](./images/watchman.png)

https://facebook.github.io/watchman/

^ Watchman is a daemon that handles this all for you.

^ runs in background, you register watches with it, and it handles the nitty gritty.

^ Adding support for this was actually the reason I started working on refactoring the autoreloader in the first place.

^ Handles git changes!

^ daemon can be shared with other projects

---

# Making it efficient: Filesystem notifications

[.code-highlight: all]
[.code-highlight: 4-6]
[.code-highlight: 8-10]

```python
import watchman

def watch_files(sleep_time=1):
    server = watchman.connect_to_server()
    for path in get_files_to_watch():
        server.watch_file(path)
    while True:
        changes = server.wait(timeout=sleep_time)
        if changes:
            exit(3)
        yield
```

^ this is pseudo-code

^ we wait for the server to send us changes

^ we don't write any platform specific code

---

# (Re-)Building an autoreloader

Three or four steps:

1. ~~Find files to monitor~~

2. ~~Wait for changes and trigger a reload~~

3. ~~Make it testable~~

4. ~~Bonus points: Make it efficient~~

---

# The aftermath

:heavy_check_mark: Much more modern, easy to extend code

:heavy_check_mark: Faster, and can use Watchman if available

:heavy_check_mark: 72 tests :tada:

:heavy_check_mark: No longer a "dark corner" of Django[^3]

[^3]: I might be biased!

^ So all good, right? 

^ I'm a genius and it worked first time

^ tests green, ship it?

^ everyone is happy?

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

---

# The aftermath

[.code-highlight: all]
[.code-highlight: 2, 10]
[.code-highlight: 6-7]

```python
def watch_file():
    last_loop = time.time()
    while True:
        for path in get_files_to_watch():
            ...
            if previous_mtime is None and mtime > last_loop:
                exit(3)
            ...
        time.sleep(1)
        last_loop = time.time()
```

^ In the Django implementation we may be watching for files that have not been created yet. 

^ limitations: cannot detect new files, or re-names

^ I wanted to detect new files that where added since the last iteration of the loop

^ previous time none, not seen before

---

![inline](./images/60-percent.jpg)

^ worked on every platform except windows.

^ doesn't work, 25% of the time

^ you get all kinds of strange behaviour.

^ across different operating systems, disks and configurations.

^ simple optimisations can bite you. Keep it really, really simple.

---

# Conclusions:

## Don't write your own autoloader.

## Use this library:

## https://github.com/Pylons/hupper

---

![inline](./images/onfido.png)

# [fit] https://onfido.com/careers

^ We provide an awesome API to verify your users identities

^ It's a really interesting problem space

^ Theoretical: What is an identity?

^ More interesting: How do we handle millions of realtime checks as fast as possible, with as little fraud as possible?



---

# Questions?

### Tom Forbes - tom@tomforb.es