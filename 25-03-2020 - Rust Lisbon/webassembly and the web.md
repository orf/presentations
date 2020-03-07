theme: poster

# Putting the Web in WebAssembly

### *Tom Forbes - Rust Lisbon 2020*

---

## I'm Tom 😎

### I love Python 🐍

### Rust interests me a *lot* 🦀

### I work at Onfido in Lisbon️ 🇵🇹

---

# [fit] In the beginning

# [fit] there was only

# [fit] JavaScript 😱

--- 

## Not everyone liked that.

---

## And so WebAssembly (*WASM*) born

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

---

# magically compiled? 🧙‍♀️

---

## wasm-pack

#### *[https://github.com/rustwasm/wasm-pack](https://github.com/rustwasm/wasm-pack)*

---

Rust + WASM + Webpack = ❤️

*`npm init rust-webpack your-package-name`*

---

# Demos

### *[https://github.com/orf/rust-lisbon-2020-demos](https://github.com/orf/rust-lisbon-2020-demos)*

---

# *Demo #1*

# Hello World

---

# The magic of *`index.js`*

---

WASM (currently) has 4 types: *int32*, *int64*, *float32* and *float64*.

That's it.

No arrays. No objects. No strings 😱

---

## *index.js* is the WASM -> JS bridge

* *manages* memory shared with WASM

* *converts* between JS and WASM types

* *encapsulates* language-specific stuff


See *[WebAssembly Interface Types: Interoperate with All the Things!](https://hacks.mozilla.org/2019/08/webassembly-interface-types/)*
from Mozilla for more information

---

# *Demo #2*

# Seed

---

 