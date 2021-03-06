#!/usr/bin/env bash

load $HOME/test/'test_helper/bats-assert/load.bash'
load $HOME/test/'test_helper/bats-support/load.bash'

test_image_name=gabrielstar/crux-base:latest
test_image_name_master=gabrielstar/crux-master:latest
test_image_name_slave=gabrielstar/crux-slave:latest
run_opts="--shm-size=1g --rm"
jmeter_test_successful_output="Err:     0 (0.00%)"

# setup_file does not work well for this, so I build docker image in first test as an ugly but stable work-around
# whover knows how to fix it, you get a beer. Rememeber this case is equivalent of setup_file.
#These tests shoudl be independent of external services so we spin mock-server as adocker container for tests

setup_file(){
  docker stop mockserver ||:
  docker run --name mockserver -d --rm -p 1080:1080 mockserver/mockserver:mockserver-5.11.1 #sets a service for tests
  until curl -X PUT "http://localhost:1080/status" -H  "accept: application/json"; do sleep 1;done #wait for service to be available
  #all requests return HTTP 200
  curl -X PUT "http://localhost:1080/expectation" -H  "Content-Type: application/json" -d "{\"httpRequest\":{\"method\":\"GET\",\"path\":\"/.*\"},\"httpResponse\":{\"statusCode\":200,\"reasonPhrase\":\"I am mocking all the stuff\"}}"
}

teardown_file(){
  docker stop mockserver
}
@test "All E2E tests use Mock Server or STS as AUT" {
  #only use localhost:9191 (sts) or localhost:1080 (mock server) as AUT for e2e feature tests
  assert_success
}

@test "Mock server is running" {
  run curl -X PUT "http://localhost:1080/status" -H  "accept: application/json"
  assert_output --partial 5.11.1
}
@test "Mock server returns 200 for any GET call" {
  run curl -v -X GET "http://localhost:1080/i_do_not_exist" -H  "accept: application/json"
  assert_output --partial "HTTP/1.1 200"
}
@test "E2E: JMeter Test works fine with Simple Table Server " {
  local test_scenario=test_table_server.jmx
  local cmd_start_sts="screen -A -m -d -S sts /jmeter/apache-jmeter-*/bin/simple-table-server.sh -DjmeterPlugin.sts.addTimestamp=true -DjmeterPlugin.sts.datasetDirectory=/test "
  local wait_for_sts="sleep 2" #time for sts to start, need to be refactored to conditional loop
  local cmd_execute_jmeter_test="jmeter -n -t $test_scenario"
  local cmd="$cmd_start_sts && $wait_for_sts && $cmd_execute_jmeter_test"
  #WHEN I run a jmeter test that use chrome headless and webdriver and I print result file to stdout
  run docker run $run_opts $test_image_name_master /bin/bash -c "$cmd"
  #Then test is a success
  assert_output --partial  "$jmeter_test_successful_output"
}

@test "E2E: JMeter Simple Table Server and Chrome Headless work fine " {

  local test_scenario=selenium_chrome_headless_sts.jmx
  local cmd_start_sts="screen -A -m -d -S sts /jmeter/apache-jmeter-*/bin/simple-table-server.sh -DjmeterPlugin.sts.addTimestamp=true -DjmeterPlugin.sts.datasetDirectory=/test "
  local wait_for_sts="sleep 2" #time for sts to start, need to be refactored to conditional loop
  local cmd_execute_jmeter_test="jmeter -n -t $test_scenario"
  local cmd="$cmd_start_sts && $wait_for_sts && $cmd_execute_jmeter_test"
  #WHEN I run a jmeter test that use chrome headless and webdriver and I print result file to stdout
  run docker run $run_opts $test_image_name_master /bin/bash -c "$cmd"
  #Then test is a success
  assert_output --partial  "$jmeter_test_successful_output"
}

@test "E2E: JMeter WebDriver Sampler scenario with Chrome Headless is run fine within the container" {
  local result_file=results.csv
  local test_scenario=selenium_test_chrome_headless.jmx
  #WHEN I run a jmeter test that use chrome headless and webdriver and I print result file to stdout
  run docker run $run_opts $test_image_name jmeter -Jwebdriver.sampleresult_class=com.googlecode.jmeter.plugins.webdriver.sampler.SampleResultWithSubs -n -l $result_file -t $test_scenario
  #Then test is a success
  refute_output --partial CannotResolveClassException
  assert_output --partial "$jmeter_test_successful_output"
}

@test "IT: Chromedriver 84 is installed " {
  run docker run $run_opts $test_image_name chromedriver --version
  #Then it is successful
  assert_output --partial "ChromeDriver 84."
}

@test "IT: Chrome 84 is installed" {
  run docker run $run_opts $test_image_name google-chrome --version
  #Then it is successful
  echo $output
  assert_output --partial "Google Chrome 84."
}

@test "IT: Python 2.7 is installed" {
  run docker run  $run_opts $test_image_name python --version
  #Then it is successful
  assert_output --partial "Python 2.7."
}

@test "IT: Groovy 2.4 is installed" {
  run docker run $run_opts $test_image_name groovy --version
  #Then it is successful
  assert_output --partial "Groovy Version: 2.4."
}

@test "IT: OpenJDK 1.8 is installed" {
  run docker run $run_opts $test_image_name java -version
  #Then it is successful
  assert_output --partial "1.8."
}

@test "IT: Chrome Headless works fine when used in python script" {
  #WHEN I run test that use chrome headless
  run docker run $run_opts $test_image_name python test.py
  #Then they are successful
  assert_success
}

@test "IT: JMeter 5.3 is present" {
  #WHEN I run test that use chrome headless
  run docker run $run_opts $test_image_name jmeter --version
  #Then they are successful
  assert_output --partial "\ 5.3"
}


@test "IT: Docker Base Image Builds Successfully" {
  docker image rm $test_image_name ||:
  run docker build --rm --no-cache -t $test_image_name -f Dockerfile .
  assert_output --partial "Successfully built"
  assert_success
}

@test "IT: Docker Master Image Builds Successfully" {
  docker image rm $test_image_name_master ||:
  run docker build -t $test_image_name_master -f Dockerfile-master .
  assert_success
}

@test "IT: Docker Slave Image Builds Successfully" {
  docker image rm $test_image_name_slave ||:
  run docker build -t $test_image_name_slave -f Dockerfile-slave .
  assert_success
}