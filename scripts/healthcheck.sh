#!/bin/bash

# Periodically Checks AMBEd is Alive by Probing UDP Port 10100 (AMBE Controller Port)
lsof -i udp:10100
