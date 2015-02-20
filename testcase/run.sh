#!/bin/sh
nim -d:release c infiniteXML.nim && nim -d:release c benchmark.nim && ./infiniteXML | ./benchmark
