import http from "k6/http";
import { check } from "k6";
import { Rate, Trend } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";
const LOGIN_ID = __ENV.LOGIN_ID || "seed_user_1";
const PASSWORD = __ENV.PASSWORD || "password";

const todoOtherDuration = new Trend("todo_other_duration", true);
const todoOtherFailed = new Rate("todo_other_failed");

export const options = {
  scenarios: {
    todo_other: {
      executor: "ramping-arrival-rate",
      startRate: 5,
      timeUnit: "1s",
      preAllocatedVUs: 20,
      maxVUs: 120,
      stages: [
        { target: 20, duration: "2m" },
        { target: 40, duration: "3m" },
        { target: 60, duration: "5m" }
      ],
      tags: { scenario: "todo_other" }
    }
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    "http_req_duration{name:todo_other}": ["p(95)<700"],
    todo_other_failed: ["rate<0.01"],
    todo_other_duration: ["p(95)<700"]
  }
};

export function setup() {
  const loginPayload = JSON.stringify({
    loginId: LOGIN_ID,
    password: PASSWORD
  });

  const loginRes = http.post(`${BASE_URL}/v1/member/auth/login`, loginPayload, {
    headers: { "Content-Type": "application/json" },
    tags: { name: "login" }
  });

  const ok = check(loginRes, {
    "login status is 200": (r) => r.status === 200,
    "login has accessToken": (r) => {
      try {
        return !!r.json("data.accessToken");
      } catch (_) {
        return false;
      }
    }
  });

  if (!ok) {
    throw new Error(
      `Login failed. status=${loginRes.status}, body=${loginRes.body}`
    );
  }

  return { accessToken: loginRes.json("data.accessToken") };
}

export default function (data) {
  const res = http.get(`${BASE_URL}/v1/todo/other`, {
    headers: {
      Authorization: `Bearer ${data.accessToken}`
    },
    tags: { name: "todo_other", endpoint: "/v1/todo/other" }
  });

  todoOtherDuration.add(res.timings.duration, { endpoint: "/v1/todo/other" });

  const success = check(res, {
    "todo_other status is 200": (r) => r.status === 200
  });

  todoOtherFailed.add(!success, { endpoint: "/v1/todo/other" });
}
