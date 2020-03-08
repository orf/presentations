theme: poster

# Putting the Web in WebAssembly

### *Tom Forbes - Rust Lisbon 2020*

---

## I'm Tom 😎

### I love Python 🐍

### Rust interests me a *lot* 🦀

### I work at Onfido in Lisbon️ 🇵🇹

^ I like the tooling, the syntax, the ecosystem and the performance.

^ I think Rust is going to continue to do amazing things in the future, and one of those areas it's going to excel 
  in is in the browser, thanks to web assembly.

^ We'll start with a really brief history of WASM

---

# [fit] In the beginning

# [fit] there was only

# [fit] JavaScript 😱

^ If you wanted to do anything dynamic in the browser you *had* to use JavaScript. 

--- 

## Not everyone liked that.

^ JS is mediocre. It's alright if you're used to it, but being forced to use a specific and in some ways weird 
  language to do anything on the web is not great.
  
^ So people wrote all kinds of things to transpile other languages to JavaScript. You have tools for Python, Ruby and 
  Elixir, Java and even C++.
  
^ These tools had a performance impact: Compiling other languages to JS produced pretty artificial code that was 
  sometimes not optimized well.
  
^ They where also hard to write: mapping language features from Elixir to JS is non-trivial.

---

## And so WebAssembly (*WASM*) born

^ This is obviously the tl;dr history of WASM, the actual history is pretty interesting and you should go read it.

---

# WASM is the fourth language to run natively in browsers

![inline fill 7%](./images/html.png) ![inline fill 50%](./images/css.jpg) ![inline fill 50%](./images/js.png) ![inline fill 10%](./images/wasm.png)

## >90%[^1] of all browsers support it *right now*

[^1]: [https://caniuse.com/#feat=wasm](https://caniuse.com/#feat=wasm)

^ If you don't care about Internet Explorer or Opera then it's much closer to 100%

---

## Basic example

```rust
// Your rust function, magically compiled to "sum.wasm"
#[wasm_bindgen]
pub fn sum(x: u32, y: u32) -> u32 {
    return x + y
}
```

```html
<!-- Your HTML page -->
<script type="text/javascript">
    WebAssembly.instantiateStreaming(fetch('sum.wasm'), {})
    .then(result => {
      console.log(result.instance.exports.sum(1, 2))
    })
</script>
```

^ Explain the code samples

^ WASM is a compiled language, and you need to pass it to this `WebAssembly.instantiateStreaming` method to load it

^ This loads and validates the WASM file incrementally as it's being downloaded.

^ Once done a object is returned with functions you can invoke

---

# magically compiled? 🧙‍♀️

^ What does that mean? 

^ Well it's not quite as simple as just running `cargo build`, and you have to fit into the 
  existing JS ecosystem

---

## wasm-pack

#### *[https://github.com/rustwasm/wasm-pack](https://github.com/rustwasm/wasm-pack)*

^ 

---

Rust + WASM + Webpack = ❤️

 *`npm install @wasm-tool/wasm-pack-plugin `*

or for a complete quickstart template:

*`npm init rust-webpack your-package-name`*

---

# Demos

### *[https://github.com/orf/rust-lisbon-2020-demos](https://github.com/orf/rust-lisbon-2020-demos)*

---

# *Demo #1*

# Hello World

---

# The magic of *`index.js`*

^ What was the index.js file that we saw? It looked auto-generated.

---

WASM (currently) has 4 types: *int32*, *int64*, *float32* and *float64*.

That's it.

No arrays. No objects. No strings 😱

^ WASM might add support for more types in the future, but it's a compilation target for a lot 
  of different languages with different semantics.

---

## *index.js* is the WASM -> JS bridge

* *manages* memory shared with WASM

* *converts* between JS and WASM types

* *encapsulates* language-specific stuff

See *[WebAssembly Interface Types: Interoperate with All the Things!](https://hacks.mozilla.org/2019/08/webassembly-interface-types/)*
from Mozilla for more information

^ Therefore a small JavaScript bridge is constructed to interface between WASM and JavaScript, and provide other 
  runtime functions to WASM.
  
^ It also creates a nice idiomatic JavaScript interface to WASM modules. 

^ We'll see later, but you can pass Rust callbacks to JavaScript functions and vice/versa, the JS bindings help a lot
  with that.

---

# *Demo #2*

# Seed

---

# The elm architecture

![inline](./images/elm.jpg)

^ Lots of projects, like Redux, took inspiration from the Elm Architecture.

---

# *Demo #2.1*

## Using the Rust ecosystem

---

# *web-sys* crate

Turns *Web IDL* into Rust bindings

```c#
[Constructor(DOMString url, optional (DOMString or DOMString[]) protocols)]
interface WebSocket : EventTarget {
    readonly attribute DOMString url;

    // networking
    attribute EventHandler onopen;
    attribute EventHandler onerror;
    attribute EventHandler onclose;

    void close([Clamp] optional unsigned short code, optional DOMString reason);
    
    void send(DOMString data);
    void send(Blob data);
    void send(ArrayBuffer data);
    void send(ArrayBufferView data);
};
```

^ This is all auto-generated into idiomatic rust bindings

---

Using Websockets from WASM

```rust
use web_sys::{MessageEvent, WebSocket};

fn websocket() {
    let ws = WebSocket::new("wss://echo.websocket.org")?;
    
    // Simplified example for brevity
    let onmessage_callback = Closure::wrap(move |e: MessageEvent| {
        let response = e
            .data()
            .as_string()
            .expect("Can't convert received data to a string");
        console_log!("message event, received data: {:?}", response);
    });

    ws.set_onmessage(Some(onmessage_callback));
}
```

---

# *Demo #3*

# The holy grail

---

# *Questions?*


### [https://tomforb.es](https://tomforb.es)

### tom@tomforb.es