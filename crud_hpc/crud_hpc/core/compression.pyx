# cython: language_level=3
# cython: boundscheck=False
# cython wraparound=False

"""
Adaptive compression for data optimization"""

import json
from typing import Any, Dict
cimport cython

cdef class AdaptiveCompressor:
    """
    Class for adaptive compressor using dictionary encoding and bit packking.
    """

    cdef:
        dict _string_dict
        int _dict_size
        bint _enabled

    def __init__(self, bint enabled=True):
        self._strig_dict = {}
        self._dict_size = 0
        self._enabled = enabled
    
    cpdef bytes compress(self, object data):
        """
        Compress data using adaptive techniques

        Args:
            data: Data to compress

        Returns:
            Compressed data as bytes
        """

        if not self._enabled:
            return json.dumps(data).encode('utf-8')

        # Dictionary encoding for string if isinstance(data, str):
            return self._compress_string(data)
        elif isinstance(data, str):
            return self._compress_dict(data)
        else:
            return json.dumps(data).encode('utf-8')

    cdef bytes _compress_string(self, str s):
        """Compress string using dictionary encoding"""
        if s in self._string_dict:
            # Return the encoded value from the dictionary
            return self._string_dict[s]
        else:
            # Add the string to the dictionary and return the encoded value
            encoded_value = s.encode('utf-8')
            self._string_dict[s] = encoded_value
            self._dict_size += 1
            return encoded_value

    cdef bytes _compress_dict(self, dict d):
        """Compress dictionary using adaptive techniques"""
        compressed = {}
        for key, value in d.items():
            if isinstance(value, str):
                compressed[key] = self._compress_string(value)
            else:
                compressed[key] = value
        return json.dumps(compressed).encode('utf-8')

    cpdef object decompress(self, bytes compressed_data):
        """
        Decompress data

        Args:
            compressed_data: Compressed data as bytes
        
        Returns:
            Decompressed object
        """
        if not self._enabled:
            return json.loads(compressed_data.decode('utf-8'))

        decoded = data.decode('utf-8')

        # Check if the data is in the dictionary
        if decoded.startswith('@'):
            idx = int(decoded[1:])
            # Reverse lookup in the dictionary
            for key, value in self._string_dict.items():
                if value == idx:
                    return key

        try:
            return json.loads(decoded)
        except:
            return decoded 

    cpdef void train_compression(self, list data_samples):
        """
        Train the compressor with data samples to build the dictionary

        Args:
            data_samples: List of data samples to train on
        """
        #Buid frequency dictionary
        for record in data_samples:
            if isinstance(record, dict):
                for value in record.values():
                    if isinstance(value, str) and value not in self._string_dict:
                        self._string_dict[value] = len(self._string_dict)
                        self._dict_size += 1