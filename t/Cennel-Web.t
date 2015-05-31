#!/bin/bash
echo "1..1"
(./perl -c lib/Cennel/Web.pm && echo "ok 1") || echo "not ok 1"
