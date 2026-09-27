//
// Copyright 2024 Signal Messenger, LLC.
// SPDX-License-Identifier: AGPL-3.0-only
//

package org.signal.libsignal.net;

import static java.nio.charset.StandardCharsets.US_ASCII;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
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

  // SWARM additions (see docs/SWARM-CHANGES.md). Nothing below contacts any server: the chat
  // connection attempts go to a proxy on 127.0.0.1 that records which host they asked for and
  // refuses every tunnel.

  private static final String REFUSAL = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n";

  @Test
  public void swarmEnvironmentsAreNumberedAsTheRustBridgeExpects() {
    assertEquals(0, Network.Environment.STAGING.value);
    assertEquals(1, Network.Environment.PRODUCTION.value);
    assertEquals(2, Network.Environment.SWARM.value);
    assertEquals(3, Network.Environment.SWARM_STAGING.value);
  }

  @Test
  public void swarmEnvironmentsIgnoreCensorshipCircumvention() {
    checkCensorshipCircumventionIsIgnored(Network.Environment.SWARM);
    checkCensorshipCircumventionIsIgnored(Network.Environment.SWARM_STAGING);
  }

  @Test
  public void swarmEnvironmentDialsOnlyTheSwarmChatHost() throws Exception {
    checkDialsOnly(Network.Environment.SWARM, "chat.swarm.green");
  }

  @Test
  public void swarmStagingEnvironmentDialsOnlyTheSwarmStagingChatHost() throws Exception {
    checkDialsOnly(Network.Environment.SWARM_STAGING, "staging.chat.swarm.green");
  }

  private static Network newNetwork(Network.Environment env) {
    return new Network(env, USER_AGENT, Map.of(), Network.BuildVariant.PRODUCTION);
  }

  private static int isUsingProxy(Network net) {
    Network.ConnectionManager manager = net.getConnectionManager();
    return manager.guardedMap(NativeTesting::TESTING_ConnectionManager_isUsingProxy);
  }

  private static void checkCensorshipCircumventionIsIgnored(Network.Environment env) {
    Network net = newNetwork(env);
    // SWARM operates no reflectors: enabling circumvention is a logged no-op, not a crash, and
    // it must not route anything through somebody else's front.
    net.setCensorshipCircumventionEnabled(true);
    assertEquals(0, isUsingProxy(net));
    net.setCensorshipCircumventionEnabled(false);
    assertEquals(0, isUsingProxy(net));
  }

  private static void checkDialsOnly(Network.Environment env, String host) throws Exception {
    List<String> requestLines;
    try (RefusingConnectProxy proxy = new RefusingConnectProxy()) {
      Network net = newNetwork(env);
      net.setProxy("http", "127.0.0.1", proxy.port(), null, null);
      assertEquals(1, isUsingProxy(net));
      // The proxy refuses the tunnel, so the attempt fails without leaving this machine.
      assertThrows(
          ExecutionException.class,
          () -> net.connectUnauthChat(new NoOpListener()).get(30, TimeUnit.SECONDS));
      requestLines = proxy.requestLines();
    }
    assertFalse("the chat connection never reached the proxy", requestLines.isEmpty());
    for (String requestLine : requestLines) {
      assertEquals("CONNECT " + host + ":443 HTTP/1.1", requestLine);
      assertFalse(requestLine, requestLine.contains("signal"));
    }
  }

  // Stands in for an HTTP CONNECT proxy on 127.0.0.1: records the request line of every tunnel
  // it is asked for, and refuses it.
  private static final class RefusingConnectProxy implements AutoCloseable {
    private final ServerSocket serverSocket;
    private final List<String> requestLines = new CopyOnWriteArrayList<>();

    RefusingConnectProxy() throws IOException {
      serverSocket = new ServerSocket(0, 50, InetAddress.getLoopbackAddress());
      Thread acceptor = new Thread(this::acceptLoop, "swarm-refusing-proxy");
      acceptor.setDaemon(true);
      acceptor.start();
    }

    int port() {
      return serverSocket.getLocalPort();
    }

    List<String> requestLines() {
      return new ArrayList<>(requestLines);
    }

    private void acceptLoop() {
      while (!serverSocket.isClosed()) {
        try (Socket client = serverSocket.accept()) {
          refuse(client);
        } catch (IOException e) {
          // Either the test closed the proxy (the loop ends) or a client went away (keep going).
        }
      }
    }

    private void refuse(Socket client) throws IOException {
      InputStreamReader input = new InputStreamReader(client.getInputStream(), US_ASCII);
      BufferedReader reader = new BufferedReader(input);
      String requestLine = reader.readLine();
      if (requestLine == null) {
        return;
      }
      requestLines.add(requestLine);
      // Skip the request headers, then refuse the tunnel.
      String header = reader.readLine();
      while (header != null && !header.isEmpty()) {
        header = reader.readLine();
      }
      OutputStream output = client.getOutputStream();
      output.write(REFUSAL.getBytes(US_ASCII));
      output.flush();
    }

    @Override
    public void close() throws IOException {
      serverSocket.close();
    }
  }
}
