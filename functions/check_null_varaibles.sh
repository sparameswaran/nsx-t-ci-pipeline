#!/bin/bash

function check_null_variables {

  for token in $(env | grep '=' | grep "^[A-Z]*" | grep '=null' | sed -e 's/=.*//g')
  do
    unset ${token}
  done
}

check_null_variables
