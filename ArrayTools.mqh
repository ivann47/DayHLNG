int ArrayPush(long& array[], long value) {
    int size = ArraySize(array);

    int newSize = ArrayResize(array, size + 1, 10);

    if (newSize != -1) array[size] = value;

    return newSize;
}
