// Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com) All Rights Reserved.
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/log;
import ballerina/time;

// ================================================================================
// COMMAND TUNNEL
// ================================================================================
// Generic plumbing for control commands the ICP tunnels through heartbeat
// responses to be executed in-process: payload parsing, at-most-once execution
// with result replay for redelivered commands, and the {commandId, httpStatus,
// body} result envelope posted back on POST /icp/commandResult. Nothing here is
// specific to any command kind — a new tunneled ControlAction only needs an
// executor (see handleTunneledCommand in main.bal, where actions are mapped to
// their executors).

# Executes one tunneled command's operation. Takes the operation request
# (`{operation, params, identity}`) and returns `{httpStatus, body}` exactly as the
# corresponding management API would have responded.
public type TunneledCommandExecutor isolated function (map<json> command) returns map<json>|error;

# Validates a tunneled command's deadline before execution. A command whose deadline
# has passed must not run — the ICP-side caller has already timed out, and a late
# mutation is worse than none. A deadline that cannot be parsed is refused the same
# way: an unassessable deadline is no license to run without one.
#
# + deadline - The ISO-8601 instant from the payload, or `()` when the command has none
# + commandId - The command's correlation ID, for the refusal message
# + return - `()` when execution may proceed, or an error saying why it must not
isolated function validateCommandDeadline(string? deadline, string commandId) returns error? {
    if deadline is () {
        return;
    }
    time:Utc|time:Error deadlineTime = time:utcFromString(deadline);
    if deadlineTime is time:Error {
        return error(string `Rejected command ${commandId}: malformed deadline '${deadline}'`, deadlineTime);
    }
    if time:utcDiffSeconds(deadlineTime, time:utcNow()) < 0d {
        return error(string `Dropped expired command ${commandId} unexecuted ` +
                string `(deadline ${deadline}) — its ICP-side caller has already timed out`);
    }
}

// Outcomes of recently executed commands, kept so a redelivered commandId (e.g. its
// result was lost after execution) replays the stored result instead of executing the
// operation twice — this is what makes tunneled mutations safe against duplicate
// delivery. A commandId is reserved atomically before execution, so concurrent
// heartbeat rounds delivering the same command cannot both execute it.
// Insertion-ordered FIFO eviction; one record so a single lock covers all structures
// (a lock statement may access only one isolated module-level variable).
//
// The capacity has to outlast the window in which the ICP may redeliver a command whose
// result was lost. A control plane that redelivers minutes later relies on finding the
// entry here: if it has been evicted, the "safe" redelivery re-executes the operation
// instead of replaying it, completing a human task twice. Ten heartbeat rounds of a full
// batch is the working figure - a batch is capped at ten reads plus ten mutations - and
// entries are also kept for a minimum age so a burst of reads cannot evict the mutation
// results that actually matter.
const int PROCESSED_COMMAND_CACHE_CAPACITY = 512;

// An entry younger than this is never evicted to make room, even when the cache is full;
// the cache grows past its capacity instead. Sustained load evicting a mutation's result
// inside the redelivery window is the failure this prevents, and a few hundred extra
// entries cost far less than an operation running twice.
const decimal PROCESSED_COMMAND_MIN_AGE_SECONDS = 300;

type ProcessedCommandCache record {|
    map<TunneledCommandResult> results = {};
    map<boolean> inFlight = {};
    string[] insertionOrder = [];
    // commandId -> when its result was stored, for the minimum-age rule.
    map<time:Utc> storedAt = {};
|};

isolated ProcessedCommandCache processedCommands = {};

// Atomically claims a commandId for execution. Returns the stored result when the
// command was already executed (replay it), `true` when this caller now owns the
// execution, and `false` when another round is executing it right now (post nothing —
// the owning execution will).
isolated function reserveOrReplay(string commandId) returns TunneledCommandResult|boolean {
    lock {
        TunneledCommandResult? cached = processedCommands.results[commandId];
        if cached is TunneledCommandResult {
            return cached.clone();
        }
        if processedCommands.inFlight.hasKey(commandId) {
            return false;
        }
        processedCommands.inFlight[commandId] = true;
        return true;
    }
}

isolated function storeCommandResult(TunneledCommandResult result) {
    lock {
        _ = processedCommands.inFlight.removeIfHasKey(result.commandId);
        if processedCommands.results.hasKey(result.commandId) {
            return;
        }
        time:Utc now = time:utcNow();
        // Evict only entries old enough to be outside the redelivery window. Stopping at the
        // first young entry keeps this O(evicted) rather than O(cache).
        while processedCommands.insertionOrder.length() >= PROCESSED_COMMAND_CACHE_CAPACITY {
            string oldest = processedCommands.insertionOrder[0];
            time:Utc? storedAt = processedCommands.storedAt[oldest];
            if storedAt is time:Utc
                    && time:utcDiffSeconds(now, storedAt) < PROCESSED_COMMAND_MIN_AGE_SECONDS {
                break;
            }
            _ = processedCommands.insertionOrder.shift();
            _ = processedCommands.results.removeIfHasKey(oldest);
            _ = processedCommands.storedAt.removeIfHasKey(oldest);
        }
        processedCommands.insertionOrder.push(result.commandId);
        processedCommands.results[result.commandId] = result.clone();
        processedCommands.storedAt[result.commandId] = now;
    }
}

# Executes one tunneled command with at-most-once semantics. Never panics or returns
# an error: every executed outcome — including "not accepted" and executor failures —
# becomes a result the ICP can deliver to the waiting caller.
#
# + payload - The command payload from the control command
# + executor - The executor for this command kind, or `()` when none is registered
# + accepted - Whether this runtime currently accepts this command kind (for workflow
#              commands, that a workflow integration is registered); `false` yields a
#              FAILED/403 result
# + return - The result to post to `POST /icp/commandResult`, or `()` when another
#            round is executing the same commandId right now (nothing to post)
isolated function executeTunneledCommand(TunneledCommandPayload payload,
        TunneledCommandExecutor? executor, boolean accepted) returns TunneledCommandResult? {
    TunneledCommandResult|boolean reservation = reserveOrReplay(payload.commandId);
    if reservation is TunneledCommandResult {
        log:printInfo(string `Replaying stored result for redelivered command: ${payload.commandId}`);
        return reservation;
    }
    if !reservation {
        log:printInfo(string `Skipping command already executing in another round: ${payload.commandId}`);
        return ();
    }

    TunneledCommandResult result;
    if executor is () || !accepted {
        // The matching capability is only advertised while both hold, so this is a
        // server-side gating bug or a config change since the last heartbeat.
        result = {
            runtimeId: currentRuntimeId,
            commandId: payload.commandId,
            status: "FAILED",
            httpStatus: 403,
            body: {"error": {"message": "Commands of this kind are not accepted by this runtime"}}
        };
    } else {
        map<json> command = {
            operation: payload.operation,
            params: payload.params,
            identity: {userId: payload.identity.userId, roles: payload.identity.roles}
        };
        map<json>|error outcome = executor(command);
        if outcome is error {
            log:printError(string `Tunneled command execution failed: ${payload.commandId}`, outcome);
            result = {
                runtimeId: currentRuntimeId,
                commandId: payload.commandId,
                status: "FAILED",
                httpStatus: 500,
                body: {"error": {"message": outcome.message()}}
            };
        } else {
            json httpStatus = outcome["httpStatus"];
            if httpStatus is int {
                result = {
                    runtimeId: currentRuntimeId,
                    commandId: payload.commandId,
                    status: "COMPLETED",
                    httpStatus: httpStatus,
                    body: outcome["body"]
                };
            } else {
                log:printError(string `Tunneled command returned an unexpected result shape: ${payload.commandId}`);
                result = {
                    runtimeId: currentRuntimeId,
                    commandId: payload.commandId,
                    status: "FAILED",
                    httpStatus: 500,
                    body: {"error": {"message": "Unexpected command result shape"}}
                };
            }
        }
    }
    storeCommandResult(result);
    return result;
}
