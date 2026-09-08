// Copyright (c) 2026, WSO2 LLC. (http://wso2.com).
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ballerina/lang.runtime;
import ballerina/log;
import ballerina/task;
import ballerina/time;

function init() returns error? {
    log:printInfo("Starting ICP agent...");

    // Load configuration
    IcpConfig config = check loadConfig();
    log:printInfo("Loaded ICP configuration: " + config.toJsonString());

    // Initialize ICP client (JWT is generated internally from config)
    IcpClient icpClient = check new (config);
    log:printInfo("ICP agent initialized with server URL: " + config.serverUrl);

    // Send initial heartbeat to register with ICP server. Fields the ICP server confirmed
    // it understands come back on this same call — no extra round-trip needed to discover
    // them.
    // A failed or rejected initial heartbeat must not stop the agent. The scheduled job below
    // retries on its normal interval and recovers on its own once the server accepts this
    // runtime - after a restart, for example, the previous incarnation's record has to age out
    // first. Returning here instead left the runtime permanently disconnected while its process
    // kept serving traffic.
    string[] supportedFields = [];
    string[]|error supportedFieldsResult = sendInitialHeartbeat(icpClient);
    if supportedFieldsResult is error {
        log:printError("Initial heartbeat registration failed; the scheduled heartbeat will retry",
                supportedFieldsResult);
    } else {
        supportedFields = supportedFieldsResult;
    }

    worker w1 returns error? {
        check startICPAgent(icpClient, config, supportedFields);
    }

}

function sendInitialHeartbeat(IcpClient icpClient) returns string[]|error {
    Heartbeat|error heartbeat = getHeartbeat();
    if heartbeat is error {
        log:printError("Failed to create initial heartbeat", heartbeat);
        return heartbeat;
    }
    HeartbeatResponse|error heartbeatResponse = icpClient->sendHeartbeat(heartbeat);
    if heartbeatResponse is error {
        log:printError("Failed to send initial heartbeat", heartbeatResponse);
        return heartbeatResponse;
    }
    if !heartbeatResponse.acknowledged {
        log:printError("Initial heartbeat not acknowledged by ICP server");
        return error("Initial heartbeat not acknowledged by ICP server");
    }
    return heartbeatResponse.supportedHeartbeatFields ?: [];
}

function startICPAgent(IcpClient icpClient, IcpConfig config, string[] supportedHeartbeatFields) returns error? {
    // Start periodic heartbeat
    HeartbeatJob heartbeatJob = check new (icpClient, <decimal>config.heartbeatInterval, supportedHeartbeatFields);
    task:JobId|task:Error result = task:scheduleJobRecurByFrequency(heartbeatJob, <decimal>config.heartbeatInterval);
    if result is task:Error {
        log:printError("Failed to start heartbeat job", result);
        return error("Heartbeat scheduling failed");
    }

    log:printInfo("ICP agent started successfully with job ID: " + result.toString());

    // Keep the main function running to allow periodic tasks to execute
    while true {
        // Sleep for a while to prevent busy waiting
        runtime:sleep(1.0);
    }
}

// Guards against overlapping heartbeat ticks. The scheduler fires `execute()` at a
// fixed frequency regardless of whether the previous tick has finished, and a tick can
// now legitimately run close to one full interval (boost follow-ups) — or past it, when
// a tunneled command is slow. HeartbeatJob's bookkeeping fields (`heartbeat`,
// `fullHeartbeatRequired`, `supportedHeartbeatFields`) are unsynchronized, so two ticks
// must never run concurrently; a tick that finds the flag held simply skips.
isolated boolean heartbeatTickInProgress = false;

isolated function tryBeginHeartbeatTick() returns boolean {
    lock {
        if heartbeatTickInProgress {
            return false;
        }
        heartbeatTickInProgress = true;
        return true;
    }
}

isolated function endHeartbeatTick() {
    lock {
        heartbeatTickInProgress = false;
    }
}

// Heartbeat job
public class HeartbeatJob {
    *task:Job;
    private final IcpClient icpClient;
    private final decimal interval;
    private int attemptCount = 0;
    // Nil until a heartbeat has been built. execute() rebuilds it on every full heartbeat, and
    // fullHeartbeatRequired starts true, so the first run always produces one.
    private Heartbeat? heartbeat = ();
    private boolean fullHeartbeatRequired = true;
    private string[] supportedHeartbeatFields;

    public function init(IcpClient icpClient, decimal interval, string[] supportedHeartbeatFields = []) returns error? {
        self.icpClient = icpClient;
        self.interval = interval;
        self.supportedHeartbeatFields = supportedHeartbeatFields;
        // Failing to build the heartbeat here must not stop the job being scheduled - that would
        // leave the runtime disconnected until its process restarts, which is the failure this
        // job exists to recover from. execute() already tolerates the same failure and retries.
        Heartbeat|error initialHeartbeat = getHeartbeat(self.supportedHeartbeatFields);
        if initialHeartbeat is error {
            log:printError("Failed to create the initial heartbeat; the scheduled heartbeat will retry",
                    initialHeartbeat);
        } else {
            self.heartbeat = initialHeartbeat;
        }
    }

    # Executes the heartbeat job: one heartbeat round, plus bounded follow-up rounds
    # while the server is actively tunneling work. A follow-up happens immediately
    # after executing a tunneled command (its result may already have unblocked the
    # next queued command) or after the server's `nextHeartbeatInSeconds` boost hint
    # (sent while a user is actively working with workflow views). Follow-ups stop
    # once the tick's real elapsed time — rounds and sleeps alike — would exceed one
    # regular interval, so a tick never runs much past the next scheduled one, which
    # then continues the boost. A tick that IS still running when the scheduler fires
    # again (a slow command, a slow server) makes the new tick a no-op instead of a
    # second concurrent round: the job's heartbeat bookkeeping fields are not
    # synchronized, and overlapping rounds would race on them.
    public function execute() {
        if !tryBeginHeartbeatTick() {
            log:printWarn("Skipping this heartbeat tick — the previous one is still running");
            return;
        }
        decimal tickStart = time:monotonicNow();
        while true {
            decimal? followUpDelay = self.heartbeatRound();
            if followUpDelay is () {
                break;
            }
            decimal remainingBudget = self.interval - (time:monotonicNow() - tickStart);
            if followUpDelay >= remainingBudget {
                break;
            }
            if followUpDelay > 0d {
                runtime:sleep(followUpDelay);
            }
        }
        endHeartbeatTick();
    }

    # Sends one heartbeat (full or delta), processes the response, and decides whether
    # a follow-up round is wanted.
    #
    # + return - Seconds to wait before the follow-up round (0 = immediately), or `()`
    #            when no follow-up is needed this tick
    function heartbeatRound() returns decimal? {
        HeartbeatResponse|error heartbeatResponse;
        // The workflow worker registers its task queue on its own schedule, often after the
        // first full heartbeat has gone out — and delta heartbeats carry no fields. Left to
        // itself, the queue would wait for an unrelated full-heartbeat trigger while the ICP
        // scoped that runtime's reads namespace-wide. A change in the live value against the
        // last published one promotes this round to a full heartbeat.
        if !self.fullHeartbeatRequired {
            Heartbeat? lastPublished = self.heartbeat;
            if lastPublished is Heartbeat && currentWorkflowTaskQueue() != lastPublished?.workflowTaskQueue {
                self.fullHeartbeatRequired = true;
            }
        }
        if (self.fullHeartbeatRequired) {
            Heartbeat|error newHeartbeat = getHeartbeat(self.supportedHeartbeatFields);
            if newHeartbeat is error {
                log:printError("Failed to create full heartbeat", newHeartbeat);
                return ();
            }
            self.heartbeat = newHeartbeat;
            log:printInfo("Sending full heartbeat to ICP server");
            heartbeatResponse = self.icpClient->sendHeartbeat(newHeartbeat);
        } else {
            Heartbeat? lastHeartbeat = self.heartbeat;
            if lastHeartbeat is () {
                // No full heartbeat has been built yet, so there is nothing to diff against.
                self.fullHeartbeatRequired = true;
                return;
            }
            // Create delta heartbeat with hash
            DeltaHeartbeat|error deltaHeartbeat = getDeltaHeartbeat(lastHeartbeat);
            if deltaHeartbeat is error {
                log:printError("Failed to create delta heartbeat", deltaHeartbeat);
                return ();
            }
            log:printDebug("Sending delta heartbeat to ICP server");
            heartbeatResponse = self.icpClient->sendDeltaHeartbeat(deltaHeartbeat);
        }
        if heartbeatResponse is error {
            log:printError("Heartbeat response error", heartbeatResponse);
            return ();
        }
        if !heartbeatResponse.acknowledged {
            return ();
        }
        self.fullHeartbeatRequired = heartbeatResponse.fullHeartbeatRequired ?: false;
        string[] newSupportedHeartbeatFields = heartbeatResponse.supportedHeartbeatFields ?: [];
        if newSupportedHeartbeatFields != self.supportedHeartbeatFields {
            // Server's understood field set changed since the last ack (e.g. it was
            // upgraded mid-connection) — send a full heartbeat next so newly available (or
            // newly unsupported) optional fields take effect promptly instead of waiting on
            // an unrelated trigger for the next full heartbeat.
            self.fullHeartbeatRequired = true;
        }
        self.supportedHeartbeatFields = newSupportedHeartbeatFields;
        log:printDebug("Heartbeat acknowledged by ICP server");
        boolean processedTunneledCommand = self.handleControlCommands(heartbeatResponse.commands);
        if processedTunneledCommand {
            // Fetch the next queued command right away — the posted result has likely
            // unblocked the ICP-side caller already.
            return 0;
        }
        int? boostHint = heartbeatResponse.nextHeartbeatInSeconds;
        if boostHint is int && boostHint > 0 && <decimal>boostHint < self.interval {
            return <decimal>boostHint;
        }
        return ();
    }

    # Handles the control commands delivered in a heartbeat response.
    #
    # + commands - The commands from the response
    # + return - `true` when at least one tunneled command was processed, so the
    #            caller can immediately fetch the next queued command
    function handleControlCommands(ControlCommand[] commands) returns boolean {
        if commands.length() == 0 {
            return false;
        }

        boolean artifactsChanged = false;
        boolean tunneledCommandProcessed = false;
        // Tunneled commands are collected here and executed concurrently once the artifact
        // commands - which mutate this runtime's own state and must stay ordered - are done.
        [ControlCommand, TunneledCommandExecutor?, boolean][] tunneledCommands = [];
        foreach ControlCommand command in commands {
            log:printInfo(string `Handling control command: ${command.toJsonString()}`);
            command.status = PENDING;

            // Handle different command actions
            error? result = ();
            match command.action {
                START|STOP => {
                    string artifactName = command.targetArtifact.name;
                    boolean isStart = command.action == START;
                    string action = isStart ? "start" : "stop";

                    log:printInfo(string `${isStart ? "Starting" : "Stopping"} listener: ${artifactName}`);

                    // Execute the control action
                    boolean|error actionResult = isStart
                        ? startListenerArtifact(artifactName)
                        : stopListenerArtifact(artifactName);

                    if actionResult is error || actionResult == false {
                        log:printError(string `Failed to ${action} listener: ${artifactName}`, actionResult is error ? actionResult : ());
                        result = actionResult is error ? actionResult : error(string `Failed to ${action} listener: ${artifactName}`);
                    } else {
                        log:printInfo(string `Successfully ${action}ed listener: ${artifactName}`);
                        artifactsChanged = true;
                    }
                }
                SET_LOGGER_LEVEL => {
                    // Parse the payload
                    string payload = command.payload ?: "";
                    if payload == "" {
                        result = error("Missing payload for SET_LOGGER_LEVEL command");
                    } else {
                        LoggerLevelPayload|error loggerPayload = payload.fromJsonStringWithType();
                        if loggerPayload is error {
                            result = error(string `Failed to parse logger level payload: ${loggerPayload.message()}`);
                        } else {
                            log:printInfo(string `Setting log level to ${loggerPayload.logLevel} for logger: ${loggerPayload.componentName}`);
                            string? packageName = loggerPayload.componentPackage;
                            string trimmedPackage = (packageName is string) ? packageName.trim() : "";
                            string loggerId = (trimmedPackage.length() > 0)
                                ? trimmedPackage + ":" + loggerPayload.componentName
                                : loggerPayload.componentName;
                            result = setLoggerLevel(loggerId, loggerPayload.logLevel);
                            if result is () {
                                log:printInfo(string `Successfully set log level for logger : ${loggerPayload.componentName}`);
                                artifactsChanged = true;
                            }
                        }
                    }
                }
                _ => {
                    // Tunneled command kinds all route through here; their actions are
                    // bound to executors in ONE place (tunneledCommandBinding), so adding
                    // a kind cannot silently miss this dispatch. An action with no
                    // binding is a wiring bug — report it FAILED rather than letting it
                    // fall through as a silent COMPLETED no-op.
                    var binding = tunneledCommandBinding(command.action);
                    if binding is () {
                        result = error(string `No handler is wired for control action ${command.action}`);
                    } else {
                        tunneledCommandProcessed = true;
                        // Executed off this strand: a batch carries the queued work of several
                        // people, and running it in sequence here made every one of them wait
                        // for the slowest (a large history is seconds of work) while the next
                        // heartbeat - and so every other command - waited for the whole batch.
                        // Each command reports its own outcome, so nothing is joined.
                        tunneledCommands.push([command, binding[0], binding[1]]);
                    }
                }
            }

            // Update command status based on result
            if result is error {
                log:printError(string `Command failed: ${command.commandId}`, result);
                command.status = FAILED;
            } else {
                command.status = COMPLETED;
            }
        }

        // Fan the tunneled commands out with a bounded number in flight, so a large batch
        // degrades into slightly later answers rather than into a saturated worker pool or a
        // rate-limited Temporal client.
        if tunneledCommands.length() > 0 {
            self.executeTunneledCommands(tunneledCommands);
        }

        if artifactsChanged {
            Heartbeat|error newHeartbeat = getHeartbeat(self.supportedHeartbeatFields);
            if newHeartbeat is error {
                log:printError("Failed to create full heartbeat after control command", newHeartbeat);
                return tunneledCommandProcessed;
            }
            self.heartbeat = newHeartbeat;
        }
        return tunneledCommandProcessed;
    }

    # Executes a batch of tunneled commands with a bounded number in flight.
    #
    # A batch carries the queued work of several people. Running it in sequence made each of
    # them wait for the slowest - a large history is seconds of work - and held up the next
    # heartbeat, and so every command after it, for the length of the whole batch.
    #
    # The batch is still waited for before returning, deliberately: the bridge asks the ICP
    # for more work only once it has finished, and that pull is the back-pressure that keeps
    # a backlog from arriving faster than it can be executed.
    #
    # + commands - The tunneled commands, each with its executor and acceptance flag
    function executeTunneledCommands([ControlCommand, TunneledCommandExecutor?, boolean][] commands) {
        // A misconfigured concurrency of 0 or less would keep chunkEnd at index and spin this
        // loop forever, wedging every later heartbeat behind the in-progress guard.
        int concurrency = int:max(1, tunneledCommandConcurrency);
        int index = 0;
        while index < commands.length() {
            int chunkEnd = index + concurrency;
            if chunkEnd > commands.length() {
                chunkEnd = commands.length();
            }
            future<error?>[] running = [];
            ControlCommand[] inChunk = [];
            foreach int i in index ..< chunkEnd {
                [ControlCommand, TunneledCommandExecutor?, boolean] item = commands[i];
                inChunk.push(item[0]);
                future<error?> pending = start self.handleTunneledCommand(item[0], item[1], item[2]);
                running.push(pending);
            }
            foreach int i in 0 ..< running.length() {
                error? outcome = wait running[i];
                if outcome is error {
                    log:printError(string `Command failed: ${inChunk[i].commandId}`, outcome);
                    inChunk[i].status = FAILED;
                } else {
                    inChunk[i].status = COMPLETED;
                }
            }
            index = chunkEnd;
        }
    }

    # Executes one tunneled command and posts its result to the ICP. A command past
    # its deadline — or carrying one that cannot be parsed — is dropped unexecuted
    # (see `validateCommandDeadline`); the drop is reported as an error so the
    # command's local status honestly reads FAILED, not COMPLETED.
    #
    # + command - The tunneled control command
    # + executor - The executor bound to this command's action (see
    #              `tunneledCommandBinding`), or `()` when none is registered
    # + accepted - Whether this runtime currently accepts this command kind
    # + return - An error when the payload is unusable, the deadline had passed or
    #            was malformed, or the result could not be delivered (the command's
    #            status is reported FAILED then)
    function handleTunneledCommand(ControlCommand command, TunneledCommandExecutor? executor,
            boolean accepted) returns error? {
        string rawPayload = command.payload ?: "";
        if rawPayload == "" {
            return error(string `Missing payload for ${command.action} command`);
        }
        TunneledCommandPayload payload = check rawPayload.fromJsonStringWithType();
        check validateCommandDeadline(payload?.deadline, payload.commandId);

        TunneledCommandResult? result = executeTunneledCommand(payload, executor, accepted);
        if result is TunneledCommandResult {
            check self.icpClient->sendCommandResult(result);
        }
    }
}

# The single place a `ControlAction` is recognized as a tunneled command kind and bound
# to its executor and acceptance flag. Adding a new tunneled kind means adding an arm
# here — the dispatch in `handleControlCommands` and the execution plumbing in
# `command_tunnel.bal` pick it up from this binding alone.
#
# Workflow management is accepted whenever a workflow integration is registered: hosting
# workflows is what makes a runtime manageable, so there is no separate flag to opt in —
# a runtime without a workflow integration has no executor and accepts nothing.
#
# + action - The control command's action
# + return - The executor (or `()` when none registered) and whether commands of this
#            kind are accepted, or `()` when the action is not a tunneled command kind
function tunneledCommandBinding(ControlAction action) returns [TunneledCommandExecutor?, boolean]? {
    match action {
        WORKFLOW_MGMT => {
            TunneledCommandExecutor? executor = workflowExecutor();
            return [executor, executor !is ()];
        }
    }
    return ();
}
