# Kata Containers Tensorflow Metrics

Kata Containers provides a series of performance tests using the
TensorFlow reference benchmarks (tf_cnn_benchmarks).
The tf_cnn_benchmarks containers TensorFlow implementations of several
popular convolutional models.

## Running the test

Individual tests can be run by hand, for example:

```
$ cd metrics/machine_learning
$ ./tensorflow.sh 25 60
```

