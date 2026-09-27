//
// Copyright 2024 Signal Messenger, LLC.
// SPDX-License-Identifier: AGPL-3.0-only
//

package org.signal.libsignal.net;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.List;
import java.util.Map;
import org.junit.Test;
import org.signal.libsignal.internal.NativeTesting;

public class NetworkTest {
  private static final String USER_AGENT = "test";

  @Test
  public void networkChange() {
    // There's no feedback from this, we're just making sure it doesn't normally crash or throw.
    var net = new Network(Network.Environment.STAGING, USER_AGENT);
    net.onNetworkChange();
  }

  // SWARM additions (see docs/SWARM-CHANGES.md). None of these contacts any server: the hostnames
  // come from the environment compiled into the library, through a testing-only bridge function.

  @Test
  public void swarmEnvironmentsAreNumberedAsTheRustBridgeExpects() {
    assertEquals(0, Network.Environment.STAGING.value);
    assertEquals(1, Network.Environment.PRODUCTION.value);
    assertEquals(2, Network.Environment.SWARM.value);
    assertEquals(3, Network.Environment.SWARM_STAGING.value);
  }

  @Test
  public void swarmEnvironmentsDialOnlySwarmHosts() {
    checkOnlySwarmHosts(Network.Environment.SWARM, "chat.swarm.green");
    checkOnlySwarmHosts(Network.Environment.SWARM_STAGING, "staging.chat.swarm.green");
  }

  @Test
  public void hostnameCheckTellsSignalEnvironmentsApart() {
    // Signal's production environment names Signal's hosts, so the SWARM checks are not vacuous.
    List<String> production = hostnames(Network.Environment.PRODUCTION);
    assertTrue(production.stream().anyMatch(hostname -> hostname.contains("signal")));
  }

  @Test
  public void swarmEnvironmentsIgnoreCensorshipCircumvention() {
    checkCensorshipCircumventionIsIgnored(Network.Environment.SWARM);
    checkCensorshipCircumventionIsIgnored(Network.Environment.SWARM_STAGING);
  }

  private static List<String> hostnames(Network.Environment env) {
    return List.of(NativeTesting.TESTING_Environment_Hostnames(env.value).split("\n"));
  }

  private static void checkOnlySwarmHosts(Network.Environment env, String chatHost) {
    List<String> hostnames = hostnames(env);
    assertEquals(chatHost, hostnames.get(0));
    for (String hostname : hostnames) {
      assertFalse(hostname, hostname.contains("signal"));
      assertTrue(hostname, hostname.matches(".*\\.swarm\\.(green|invalid)"));
    }
  }

  private static int isUsingProxy(Network net) {
    Network.ConnectionManager manager = net.getConnectionManager();
    return manager.guardedMap(NativeTesting::TESTING_ConnectionManager_isUsingProxy);
  }

  private static void checkCensorshipCircumventionIsIgnored(Network.Environment env) {
    Network net = new Network(env, USER_AGENT, Map.of(), Network.BuildVariant.PRODUCTION);
    // SWARM operates no reflectors: enabling circumvention is a logged no-op, not a crash, and
    // it must not route anything through somebody else's front.
    net.setCensorshipCircumventionEnabled(true);
    assertEquals(0, isUsingProxy(net));
    net.setCensorshipCircumventionEnabled(false);
    assertEquals(0, isUsingProxy(net));
  }
}
