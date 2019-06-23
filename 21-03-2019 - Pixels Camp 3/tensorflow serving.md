theme: next

# Tensorflow Serving in Production

### Tom Forbes - Pixels Camp 2019

--- 

# Onfido automates identity verification.

## We use a lot of machine learning to do this.

---

# In the beginning this is how we deployed our TensorFlow models

```python
from flask import App, request, jsonify
from .models import load_tensorflow_model

app = App(__name__)
model = load_tensorflow_model()

@app.route('/process')
def process():
    result = model.process(request.data)
    return jsonify(result)
```

---

# While this is simple, there are a few problems with this approach

---

# Models are large

## Loading a TensorFlow model in Python adds memory overhead

### ~25% just for Python modules like numpy, tensorflow, scikit

---

# Flask is single threaded

## Models can also take a long time to execute, blocking other requests

---

# Multiple processes load the model multiple times :scream:

---

# :dollar: :dollar: :dollar: :dollar: :dollar: :dollar: 

--- 

# Solution: Tensorflow Serving

## `docker run -v/models:/models tensorflow/serving `

---

# TensorFlow Serving

* Written in C++
* Very low overhead
* Loads your models and exposes a REST or gRPC API for them
* Services call these remote models

---

# Example Request

### https://www.tensorflow.org/tfx/serving/api_rest

```
$ curl -d '{"instances": [1.0,2.0,5.0]}' \
  -X POST http://serving/v1/models/my_model:predict
{
    "predictions": [3.5, 4.0, 5.5]
}
```

---

# Huge cost savings!

---

# Real World Example

**Before Tensorflow Serving:**

Service X ran 16 pods at peak load, 4 workers per pod.

Used ~60Gb of memory in total.

**After Tensorflow Serving:**

The whole production traffic for this model could be handled by a **single pod** with 4GB memory.

12GB in total with 3 pods for redundancy.

---

# It's a beast. 

---

# It can transparently batch multiple requests

---

# It can be optimized for your CPU architecture

## Doing this for the Python package is _really_ annoying

---

# Problem:

## It's written in C++

^ It's not really extensible. We wrote a simple asynchronous Python sidecar pod that received the requests 
and added metrics.

---

# Problem:

## Model data travels over the network

^ Inferences are individually *slower* due to the overhead, but you get a lot more throughput

---

# Problem:

## It really wants you to do live reloading of models

^ It live checks for new models. Can't really disable that. 

---

# Problem:

## It uncovers weird issues with your models

^ One model would convert an image into a large matrix of RGB values. Serializing and transmitting this was redundant

^ One model was annotated to return 32 bit floats, but other code expected 64 bit floats. This worked in pure-python.

---

# We are hiring in Lisbon!

## onfido.com/careers