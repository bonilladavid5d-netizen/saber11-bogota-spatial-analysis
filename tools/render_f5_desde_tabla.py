#!/usr/bin/env python3
"""Regenera solo F5 desde la tabla 13 ya estimada; no ajusta modelos.
Auxiliar utilizado en la revision v4.1. El generador ordinario sigue en R/05_modelos.R.
Uso opcional: python3 tools/render_f5_desde_tabla.py
"""
from pathlib import Path
import csv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

ROOT = Path(__file__).resolve().parents[1]
TABLE = ROOT / "outputs/portafolio/tablas/13_impactos_sdm.csv"
OUT = ROOT / "outputs/portafolio/figuras/f5_impactos_sdm.png"
labels = {
    "estrato_promedio": "Estrato promedio del hogar (+1 unidad)",
    "prop_oficial": "Colegio oficial (+10 p.p.)",
    "prop_internet_hogar": "Internet en casa (+10 p.p.)",
    "prop_jornada_completa": "Jornada completa (+10 p.p.)",
    "prop_calendario_a": "Calendario A (+10 p.p.)",
    "prop_genero_femenino": "Mujeres (+10 p.p.)",
    "n_estudiantes_log": "Tamaño de la sede (+1 log-punto)",
}
with TABLE.open(encoding="utf-8", newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) == 7 and {r["variable"] for r in rows} == set(labels)
for row in rows:
    factor = 0.1 if row["variable"].startswith("prop_") else 1.0
    for effect in ("directo", "indirecto", "total"):
        expected = float(row[effect]) * factor
        actual = float(row[effect + "_presentado"])
        assert abs(expected - actual) <= 0.0000051, (row["variable"], effect)
rows.sort(key=lambda r: float(r["directo_presentado"]))
colours = {"directo": "#2166AC", "indirecto": "#B35806", "total": "#762A83"}
display = {"directo": "Directo", "indirecto": "Indirecto", "total": "Total"}
offset = {"directo": 0.22, "indirecto": 0.0, "total": -0.22}
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10})
fig, ax = plt.subplots(figsize=(11, 6.9), dpi=240)
fig.patch.set_facecolor("#FAFAF9")
ax.set_facecolor("#FAFAF9")
fig.subplots_adjust(left=0.335, right=0.965, top=0.73, bottom=0.24)
ax.set_axisbelow(True)
ax.grid(axis="x", color="#E1E1E1", linewidth=0.65)
ax.grid(axis="y", color="#EBEBEB", linewidth=0.65)
ax.axvline(0, color="#898989", linewidth=0.9)
for i, row in enumerate(rows):
    for effect in ("directo", "indirecto", "total"):
        significant = float(row["p_" + effect]) < 0.05
        ax.scatter(float(row[effect + "_presentado"]), i + offset[effect], s=44,
                   facecolors=colours[effect] if significant else "#FAFAF9",
                   edgecolors=colours[effect], linewidth=1.0, zorder=3)
ax.set_yticks(range(len(rows)), [labels[r["variable"]] for r in rows])
ax.set_ylim(-0.65, len(rows)-0.35)
ax.set_xlim(-0.08, 0.405)
ax.tick_params(axis="both", length=0, labelcolor="#424242", pad=8)
ax.set_xlabel("Cambio asociado en unidades z nacionales", labelpad=11)
for spine in ax.spines.values():
    spine.set_visible(False)
fig.text(0.035, 0.94, "Impactos directos, indirectos y totales del SDM",
         fontsize=16, fontweight="bold", ha="left")
fig.text(0.035, 0.896, "Cada punto usa el cambio indicado en su fila. Asociaciones entre agregados sede-año.",
         fontsize=10.7, color="#626262", ha="left")
handles = [Line2D([0], [0], marker="o", linestyle="", markersize=6,
                  color=colours[e], label=display[e]) for e in colours]
handles += [
    Line2D([0], [0], marker="o", linestyle="", color="#333333", markersize=6,
           markerfacecolor="#333333", label="p < 0,05"),
    Line2D([0], [0], marker="o", linestyle="", color="#333333", markersize=6,
           markerfacecolor="#FAFAF9", label="p ≥ 0,05"),
]
fig.legend(handles=handles, loc="upper center", bbox_to_anchor=(0.60, 0.853),
           ncol=5, frameon=False, fontsize=9.3, columnspacing=1.4, handletextpad=0.45)
caption = (
    "Descomposición de LeSage y Pace: 1.000 simulaciones. Tabla 13; no implica efectos causales.\n"
    "Significancia nominal bajo el modelo pooled, sin corrección por dependencia temporal dentro de sede.\n"
    "Fuente: ICFES Saber 11 (2016–2024), catálogo de sedes 2025 (SDP/IDECA) y elaboración del proyecto."
)
fig.text(0.335, 0.085, caption, ha="left", va="bottom", fontsize=8.4,
         color="#666666", linespacing=1.55)
fig.savefig(OUT, facecolor=fig.get_facecolor())
plt.close(fig)
print(f"F5 regenerada desde {TABLE.name}: 21 puntos, escala verificada; sin reestimación.")

