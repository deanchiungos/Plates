const STATES = [
  ["AL","Alabama",4],["AK","Alaska",10],["AZ","Arizona",5],["AR","Arkansas",5],["CA","California",2],
  ["CO","Colorado",4],["CT","Connecticut",2],["DE","Delaware",6],["FL","Florida",2],["GA","Georgia",3],
  ["HI","Hawaii",10],["ID","Idaho",8],["IL","Illinois",3],["IN","Indiana",4],["IA","Iowa",6],
  ["KS","Kansas",7],["KY","Kentucky",5],["LA","Louisiana",5],["ME","Maine",6],["MD","Maryland",3],
  ["MA","Massachusetts",2],["MI","Michigan",4],["MN","Minnesota",5],["MS","Mississippi",6],["MO","Missouri",5],
  ["MT","Montana",8],["NE","Nebraska",8],["NV","Nevada",6],["NH","New Hampshire",5],["NJ","New Jersey",1],
  ["NM","New Mexico",7],["NY","New York",1],["NC","North Carolina",3],["ND","North Dakota",9],["OH","Ohio",3],
  ["OK","Oklahoma",6],["OR","Oregon",6],["PA","Pennsylvania",2],["RI","Rhode Island",6],["SC","South Carolina",4],
  ["SD","South Dakota",9],["TN","Tennessee",4],["TX","Texas",2],["UT","Utah",6],["VT","Vermont",7],
  ["VA","Virginia",3],["WA","Washington",5],["WV","West Virginia",7],["WI","Wisconsin",5],["WY","Wyoming",9]
];

const STORAGE_KEY = "plates-mvp-v1";

let state = JSON.parse(localStorage.getItem(STORAGE_KEY)) || {
  mode: "classic",
  sightings: {}
};

const grid = document.getElementById("statesGrid");
const modeSelect = document.getElementById("modeSelect");
const scoreEl = document.getElementById("score");
const collectedEl = document.getElementById("collected");
const totalSightingsEl = document.getElementById("totalSightings");
const recapEl = document.getElementById("recap");

modeSelect.value = state.mode;

function save() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function getCount(abbr) {
  return state.sightings[abbr] || 0;
}

function calculateScore() {
  return STATES.reduce((sum, [abbr, name, weight]) => {
    const count = getCount(abbr);
    if (state.mode === "classic") return sum + (count > 0 ? 1 : 0);
    if (state.mode === "weighted") return sum + (count > 0 ? weight : 0);
    if (state.mode === "unlimited") return sum + (count * weight);
    return sum;
  }, 0);
}

function render() {
  grid.innerHTML = "";

  STATES.forEach(([abbr, name, weight]) => {
    const count = getCount(abbr);
    const btn = document.createElement("button");
    btn.className = "state" + (count > 0 ? " collected" : "");
    btn.innerHTML = `
      <strong>${abbr}</strong>
      <small>${name}</small>
      <small>value: ${weight}</small>
      ${count > 0 ? `<small class="count">x${count}</small>` : ""}
    `;

    btn.onclick = () => {
      if (state.mode === "classic" || state.mode === "weighted") {
        state.sightings[abbr] = count > 0 ? 0 : 1;
      } else {
        state.sightings[abbr] = count + 1;
      }
      save();
      render();
    };

    btn.oncontextmenu = (e) => {
      e.preventDefault();
      if (getCount(abbr) > 0) {
        state.sightings[abbr] = getCount(abbr) - 1;
        if (state.sightings[abbr] <= 0) delete state.sightings[abbr];
        save();
        render();
      }
    };

    grid.appendChild(btn);
  });

  const collected = STATES.filter(([abbr]) => getCount(abbr) > 0).length;
  const totalSightings = Object.values(state.sightings).reduce((a,b) => a + b, 0);
  const score = calculateScore();

  scoreEl.textContent = score;
  collectedEl.textContent = `${collected}/50`;
  totalSightingsEl.textContent = totalSightings;

  const missing = STATES.filter(([abbr]) => getCount(abbr) === 0).map(([abbr]) => abbr);
  const found = STATES.filter(([abbr]) => getCount(abbr) > 0).map(([abbr]) => abbr);

  recapEl.textContent = found.length
    ? `You found ${collected} states, scored ${score} points, and logged ${totalSightings} total sightings. Missing: ${missing.slice(0, 10).join(", ")}${missing.length > 10 ? "..." : ""}`
    : "Start spotting plates.";
}

modeSelect.addEventListener("change", (e) => {
  state.mode = e.target.value;
  save();
  render();
});

document.getElementById("resetBtn").onclick = () => {
  if (confirm("Reset your PLATES game?")) {
    state.sightings = {};
    save();
    render();
  }
};

document.getElementById("shareBtn").onclick = async () => {
  const text = `PLATES recap: ${collectedEl.textContent} states, ${scoreEl.textContent} points, ${totalSightingsEl.textContent} sightings.`;
  try {
    await navigator.clipboard.writeText(text);
    alert("Recap copied.");
  } catch {
    alert(text);
  }
};

render();
