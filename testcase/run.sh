#!/bin/sh
nim c infiniteXML.nim && nim c benchmark.nim && ./infiniteXML | ./benchmark
