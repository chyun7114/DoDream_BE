import http from "k6/http";
import { check } from "k6";
import { Rate, Trend } from "k6/metrics";
import exec from "k6/execution";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";
const PASSWORD = __ENV.PASSWORD || "password";
const USER_PREFIX = __ENV.USER_PREFIX || "seed_user_";
const USER_START = Number(__ENV.USER_START || 1);
const USER_COUNT = Number(__ENV.USER_COUNT || 1000);
const START_RATE = Number(__ENV.START_RATE || 20);
const STAGE1_TARGET = Number(__ENV.STAGE1_TARGET || 100);
const STAGE2_TARGET = Number(__ENV.STAGE2_TARGET || 200);
const STAGE3_TARGET = Number(__ENV.STAGE3_TARGET || 400);
const PRE_ALLOCATED_VUS = Number(__ENV.PRE_ALLOCATED_VUS || 80);
const MAX_VUS = Number(__ENV.MAX_VUS || 500);
const ENABLE_TOKEN_PREWARM =
  (__ENV.ENABLE_TOKEN_PREWARM || "true").toLowerCase() === "true";
const PREWARM_USER_COUNT = Number(__ENV.PREWARM_USER_COUNT || USER_COUNT);
const ENABLE_WARMUP_SCENARIO =
  (__ENV.ENABLE_WARMUP_SCENARIO || "true").toLowerCase() === "true";
const WARMUP_DURATION = __ENV.WARMUP_DURATION || "1m";
const WARMUP_RATE = Number(__ENV.WARMUP_RATE || 20);
const WARMUP_PRE_ALLOCATED_VUS = Number(__ENV.WARMUP_PRE_ALLOCATED_VUS || 20);
const WARMUP_MAX_VUS = Number(__ENV.WARMUP_MAX_VUS || 60);

const todoOtherDuration = new Trend("todo_other_duration", true);
const todoOtherFailed = new Rate("todo_other_failed");
const loginFailed = new Rate("todo_other_login_failed");

let cachedToken = null;
let cachedLoginId = null;

const scenarios = {};
if (ENABLE_WARMUP_SCENARIO) {
  scenarios.todo_other_warmup = {
    executor: "constant-arrival-rate",
    rate: WARMUP_RATE,
    timeUnit: "1s",
    duration: WARMUP_DURATION,
    preAllocatedVUs: WARMUP_PRE_ALLOCATED_VUS,
    maxVUs: WARMUP_MAX_VUS,
    exec: "warmup",
    tags: { scenario: "todo_other_warmup" },
  };
}

scenarios.todo_other = {
  executor: "ramping-arrival-rate",
  startTime: ENABLE_WARMUP_SCENARIO ? WARMUP_DURATION : "0s",
  startRate: START_RATE,
  timeUnit: "1s",
  preAllocatedVUs: PRE_ALLOCATED_VUS,
  maxVUs: MAX_VUS,
  stages: [
    { target: STAGE1_TARGET, duration: "2m" },
    { target: STAGE2_TARGET, duration: "3m" },
    { target: STAGE3_TARGET, duration: "5m" },
  ],
  exec: "main",
  tags: { scenario: "todo_other" },
};

export const options = {
  scenarios,
  thresholds: {
    http_req_failed: ["rate<0.01"],
    "http_req_duration{name:todo_other}": ["p(95)<700"],
    todo_other_failed: ["rate<0.01"],
    todo_other_duration: ["p(95)<700"],
    todo_other_login_failed: ["rate==0"],
  },
};

function getVuLoginId() {
  const vuIdx = exec.vu.idInTest || 1;
  const userOffset = (vuIdx - 1) % USER_COUNT;
  return `${USER_PREFIX}${USER_START + userOffset}`;
}

function loginAndGetToken(loginId, tagName = "login") {
  const loginPayload = JSON.stringify({
    loginId,
    password: PASSWORD,
  });

  const loginRes = http.post(`${BASE_URL}/v1/member/auth/login`, loginPayload, {
    headers: { "Content-Type": "application/json" },
    tags: { name: tagName, endpoint: "/v1/member/auth/login" },
  });

  const ok = check(loginRes, {
    "login status is 200": (r) => r.status === 200,
    "login has accessToken": (r) => {
      try {
        return !!r.json("data.accessToken");
      } catch (_) {
        return false;
      }
    },
  });

  if (!ok) {
    loginFailed.add(true);
    throw new Error(
      `Login failed for ${loginId}. status=${loginRes.status}, body=${loginRes.body}`,
    );
  }

  loginFailed.add(false);
  return loginRes.json("data.accessToken");
}

export function setup() {
  if (!ENABLE_TOKEN_PREWARM) {
    return { tokenByLoginId: {} };
  }

  const tokenByLoginId = {};
  const targetCount = Math.min(PREWARM_USER_COUNT, USER_COUNT);
  for (let i = 0; i < targetCount; i += 1) {
    const loginId = `${USER_PREFIX}${USER_START + i}`;
    tokenByLoginId[loginId] = loginAndGetToken(loginId, "login_setup");
  }

  return { tokenByLoginId };
}

function getToken(setupData, loginId) {
  if (cachedToken && cachedLoginId === loginId) {
    return cachedToken;
  }

  const prewarmedToken =
    setupData && setupData.tokenByLoginId && setupData.tokenByLoginId[loginId];

  if (prewarmedToken) {
    cachedToken = prewarmedToken;
    cachedLoginId = loginId;
    return cachedToken;
  }

  cachedToken = loginAndGetToken(loginId, "login_runtime");
  cachedLoginId = loginId;
  return cachedToken;
}

function runTodoOther(setupData) {
  const loginId = getVuLoginId();
  const token = getToken(setupData, loginId);

  const res = http.get(`${BASE_URL}/v1/todo/other`, {
    headers: {
      Authorization: `Bearer ${token}`,
    },
    tags: { name: "todo_other", endpoint: "/v1/todo/other", login_id: loginId },
  });

  todoOtherDuration.add(res.timings.duration, { endpoint: "/v1/todo/other" });

  const success = check(res, {
    "todo_other status is 200": (r) => r.status === 200,
  });

  todoOtherFailed.add(!success, { endpoint: "/v1/todo/other" });
}

export function warmup(setupData) {
  runTodoOther(setupData);
}

export function main(setupData) {
  runTodoOther(setupData);
}
