"""Generate the two .drawio files for the hybrid migration and DR repo."""
import sys
from html import escape

OUTDIR = sys.argv[1]

C = {"storage": "#7AA116", "integration": "#E7157B", "compute": "#ED7100", "database": "#C925D1",
     "analytics": "#8C4FFF", "management": "#E7157B", "security": "#DD344C", "cost": "#7AA116"}
INK = "#232F3E"
EDGE = "#545B64"
RED = "#D13212"


class Doc:
    def __init__(self, name, w, h):
        self.name, self.w, self.h = name, w, h
        self.cells = []
        self.n = 2
        self.org = {"1": (0, 0)}  # absolute origin of each container; all coordinates passed in are absolute

    def _id(self):
        self.n += 1
        return f"c{self.n}"

    def add(self, value, style, x, y, w, h, parent="1", vertex=True):
        i = self._id()
        value = value.replace("\n", "<br>")
        self.org[i] = (x, y)
        px, py = self.org[parent]
        x, y = x - px, y - py
        self.cells.append(
            f'<mxCell id="{i}" value="{escape(value)}" style="{style}" vertex="1" parent="{parent}">'
            f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        return i

    def group(self, label, kind, x, y, w, h, parent="1", fs=12):
        styles = {
            "cloud": f"grIcon=mxgraph.aws4.group_aws_cloud_alt;strokeColor={INK};fontColor={INK};dashed=0;",
            "region": "grIcon=mxgraph.aws4.group_region;strokeColor=#00A4A6;fontColor=#147EBA;dashed=1;",
            "account": "grIcon=mxgraph.aws4.group_account;strokeColor=#CD2264;fontColor=#CD2264;dashed=0;",
            "office": f"grIcon=mxgraph.aws4.group_corporate_data_center;strokeColor=#7D8998;fontColor={INK};dashed=0;",
            "vpc": "grIcon=mxgraph.aws4.group_vpc;strokeColor=#8C4FFF;fontColor=#8C4FFF;dashed=0;",
            "vpc_off": "grIcon=mxgraph.aws4.group_vpc;strokeColor=#8C4FFF;fontColor=#8C4FFF;dashed=1;",
            "public": "grIcon=mxgraph.aws4.group_security_group;strokeColor=#7AA116;fontColor=#248814;dashed=0;",
            "private": "grIcon=mxgraph.aws4.group_security_group;strokeColor=#00A4A6;fontColor=#147EBA;dashed=0;",
        }
        st = ("points=[];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=%d;fontStyle=1;"
              "container=1;pointerEvents=0;collapsible=0;recursiveResize=0;shape=mxgraph.aws4.group;"
              "fillColor=none;verticalAlign=top;align=left;spacingLeft=30;" % fs) + styles[kind]
        return self.add(label, st, x, y, w, h, parent)

    def box(self, label, x, y, w, h, parent="1", color="#879196", fs=12):
        st = (f"fillColor=none;strokeColor={color};dashed=1;verticalAlign=top;fontStyle=1;fontColor={color};"
              f"whiteSpace=wrap;html=1;align=left;spacingLeft=10;spacingTop=4;fontSize={fs};rounded=1;arcSize=3;container=1;collapsible=0;")
        return self.add(label, st, x, y, w, h, parent)

    @staticmethod
    def lab(pos):
        return {"below": "verticalLabelPosition=bottom;verticalAlign=top;align=center;",
                "above": "verticalLabelPosition=top;verticalAlign=bottom;align=center;",
                "right": "labelPosition=right;verticalLabelPosition=middle;align=left;verticalAlign=middle;spacingLeft=4;",
                "left": "labelPosition=left;verticalLabelPosition=middle;align=right;verticalAlign=middle;spacingRight=4;"}[pos]

    def res(self, label, icon, cat, x, y, parent="1", s=64, fs=12, pos="below"):
        st = (f"sketch=0;outlineConnect=0;fontColor={INK};gradientColor=none;fillColor={C[cat]};strokeColor=#ffffff;"
              f"dashed=0;html=1;fontSize={fs};" + self.lab(pos) +
              f"aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{icon};")
        return self.add(label, st, x, y, s, s, parent)

    def shape(self, label, shp, color, x, y, w=52, h=52, parent="1", fs=12, pos="below"):
        st = (f"sketch=0;outlineConnect=0;fontColor={INK};gradientColor=none;fillColor={color};strokeColor=none;"
              f"dashed=0;html=1;fontSize={fs};" + self.lab(pos) +
              f"aspect=fixed;pointerEvents=1;shape=mxgraph.aws4.{shp};")
        return self.add(label, st, x, y, w, h, parent)

    def text(self, label, x, y, w, h, fs=12, bold=False, color=INK, align="left", parent="1"):
        st = (f"text;html=1;strokeColor=none;fillColor=none;align={align};verticalAlign=top;whiteSpace=wrap;"
              f"fontSize={fs};fontColor={color};fontStyle={1 if bold else 0};")
        return self.add(label, st, x, y, w, h, parent)

    def badge(self, n, x, y, parent="1", d=24, fs=12):
        st = (f"ellipse;whiteSpace=wrap;html=1;aspect=fixed;fillColor={INK};strokeColor=none;fontColor=#FFFFFF;"
              f"fontStyle=1;fontSize={fs};")
        return self.add(str(n), st, x, y, d, d, parent)

    def gh(self, label, x, y, w=150, h=56, parent="1", fs=12):
        st = (f"rounded=1;whiteSpace=wrap;html=1;fillColor={INK};strokeColor=none;fontColor=#FFFFFF;fontStyle=1;"
              f"fontSize={fs};")
        return self.add(label, st, x, y, w, h, parent)

    def edge(self, src, dst, label="", color=EDGE, dashed=False, w=2, ex=None, ey=None, nx=None, ny=None, fs=11, via=None):
        i = self._id()
        st = (f"edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=block;endFill=1;strokeColor={color};"
              f"strokeWidth={w};fontSize={fs};fontColor={color};labelBackgroundColor=#FFFFFF;"
              + ("dashed=1;dashPattern=6 4;" if dashed else ""))
        if ex is not None:
            st += f"exitX={ex};exitY={ey};exitDx=0;exitDy=0;"
        if nx is not None:
            st += f"entryX={nx};entryY={ny};entryDx=0;entryDy=0;"
        self.cells.append(
            f'<mxCell id="{i}" value="{escape(label.replace(chr(10), "<br>"))}" style="{st}" edge="1" parent="1" source="{src}" target="{dst}">'
            f'<mxGeometry relative="1" as="geometry">'
            + ('<Array as="points">' + "".join(f'<mxPoint x="{px}" y="{py}"/>' for px, py in via) + '</Array>' if via else "")
            + '</mxGeometry></mxCell>')
        return i

    def xml(self):
        return (f'<mxfile host="drawio"><diagram name="{escape(self.name)}">'
                f'<mxGraphModel dx="0" dy="0" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" '
                f'fold="1" page="1" pageScale="1" pageWidth="{self.w}" pageHeight="{self.h}" background="#FFFFFF" math="0" shadow="0">'
                '<root><mxCell id="0"/><mxCell id="1" parent="0"/>'
                + "".join(self.cells) + "</root></mxGraphModel></diagram></mxfile>")



# =====================================================================
# 1. Detailed architecture (README). All coordinates absolute.


# =====================================================================
# Measured results, read from the files the scripts write. Nothing typed in by hand.
# =====================================================================
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent


def measured():
    out = {}
    mig = HERE / "migration-results.md"
    if mig.exists():
        m = re.search(r"\*\*(\d+) seconds\*\*", mig.read_text())
        out["cutover"] = m and m.group(1)
    dr = HERE / "dr-drill-results.md"
    if dr.exists():
        t = dr.read_text()
        out["rto"] = re.search(r"RTO\).*?\*\*(\d+) seconds\*\*", t).group(1)
        out["rpo"] = re.search(r"RPO\).*?\*\*(.+?) seconds\*\*", t).group(1)
    return out


M = measured()


def mins(s):
    s = int(s)
    return (f"{s // 60} min {s % 60} s" if s % 60 else f"{s // 60} min") if s >= 60 else f"{s} s"


def loss(r):
    """'more than 600' -> 'more than 10 min'; '42' -> '42 s'."""
    n = int(r.split()[-1])
    return ("more than " if r.startswith("more") else "") + (mins(n) if n >= 60 else f"{n} s")


TEAL = "#00A4A6"

# =====================================================================
# 1. Full architecture. All coordinates absolute.
# =====================================================================
d = Doc("Hybrid migration with disaster recovery", 2120, 1060)
d.add("", "rounded=0;fillColor=#FFFFFF;strokeColor=none;", 0, 0, 2120, 1060)
d.text("Hybrid migration with disaster recovery", 30, 20, 900, 34, fs=24, bold=True)
d.text("Reference architecture, built with Terraform", 30, 56, 900, 22, fs=14, color="#545B64")

staff = d.shape("Office staff", "users", INK, 150, 112, 52, 52, pos="left")

office = d.group("Company office (on-premises)", "office", 40, 210, 300, 420)
oapp = d.shape("Job tracker app\n(Docker)", "traditional_server", INK, 190, 252, 40, 60, parent=office)
odb = d.shape("PostgreSQL 17", "generic_database", INK, 86, 344, 44, 56, parent=office)
ofiles = d.shape("Uploaded files", "documents", INK, 86, 520, 46, 56, parent=office)

cloud = d.group("AWS Cloud", "cloud", 380, 110, 1300, 920)
lon = d.group("Region: eu-west-2 (London), primary", "region", 410, 160, 1240, 430, parent=cloud)
s3 = d.res("Files bucket (S3)\nuploads, releases, dumps", "s3", "storage", 450, 340, parent=lon, pos="above")
vpc = d.group("VPC 10.20.0.0/16", "vpc", 620, 205, 660, 360, parent=lon)
pub = d.group("Public subnet", "public", 650, 260, 290, 280, parent=vpc)
prv = d.group("Private subnet", "private", 970, 260, 280, 280, parent=vpc)
ec2 = d.res("App server (EC2 t4g.micro)\nno SSH, IMDSv2 only", "ec2", "compute", 763, 340, parent=pub)
rds = d.res("PostgreSQL 17 (RDS)\nencrypted, not public", "rds", "database", 1078, 340, parent=prv)
ssm = d.res("Run Command\n(Systems Manager)", "systems_manager", "management", 1430, 240, parent=lon)
sec = d.res("Database password\n(Secrets Manager)\nrotated by RDS", "secrets_manager", "security", 1430, 420, parent=lon)

irl = d.group("Region: eu-west-1 (Ireland), pilot light", "region", 410, 640, 1240, 360, parent=cloud)
s3r = d.res("Replica bucket (S3)", "s3", "storage", 450, 700, parent=irl, pos="right")
bk = d.res("Replicated backups\nsnapshots and\ntransaction logs", "rds", "database", 1078, 700, parent=irl, pos="right")
dvpc = d.group("VPC 10.30.0.0/16, built only on failover (dr_active = true)", "vpc_off", 620, 800, 660, 170, parent=irl)
dec2 = d.res("App server (EC2)", "ec2", "compute", 763, 856, parent=dvpc)
drds = d.res("PostgreSQL (RDS)\nrestored to the latest\nrestorable time", "rds", "database", 1078, 856, parent=dvpc, pos="right")

d.edge(staff, oapp, ex=0.5, ey=1, nx=0.5, ny=0)
d.edge(staff, ec2, "HTTP, office IP only (after cutover)", ex=1, ey=0.5, nx=0.25, ny=0)
d.edge(oapp, odb, ex=0, ey=0.5, nx=0.5, ny=0)
d.edge(odb, s3, "pg_dump over HTTPS", ex=1, ey=0.5, nx=0, ny=0.3)
d.edge(ofiles, s3, "S3 sync, SHA-256 checked", ex=1, ey=0.5, nx=0, ny=0.8)
d.edge(s3, ec2, "dump, release")
d.edge(ec2, rds, "restore, then SQL")
d.edge(ssm, ec2, "runs restore and checks", ex=0, ey=0.5, nx=0.8, ny=0, via=[(1340, 272), (1340, 232), (814, 232)])
d.edge(rds, sec, "password", ex=1, ey=0.25, nx=0.5, ny=0, via=[(1462, 356)])
d.edge(s3, s3r, "S3 replication", color=TEAL, dashed=True, ex=0.5, ey=1, nx=0.5, ny=0)
d.edge(rds, bk, "", color=TEAL, dashed=True, ex=1, ey=0.75, nx=0.5, ny=0,
       via=[(1300, 388), (1300, 660), (1110, 660)])
d.edge(bk, drds, "point-in-time restore", color=TEAL, dashed=True)
d.edge(s3r, dec2, "release, files", color=TEAL, dashed=True, ex=0.5, ey=1, nx=0, ny=0.5, via=[(482, 888)])
d.edge(dec2, drds)

d.text("cross-region backup\nreplication", 1310, 600, 160, 34, fs=11, color=TEAL)

for n, x, y in [(1, 240, 256), (2, 150, 330), (3, 1500, 232), (4, 950, 316), (5, 1270, 604), (6, 1040, 836)]:
    d.badge(n, x, y)

lx = 1730
d.text("How it works", lx, 110, 360, 24, fs=15, bold=True)
steps = [
    "Writes stop on the company server, so nothing changes mid-copy.",
    "The database dump and every uploaded file go to S3 over HTTPS. Each file's SHA-256 is checked.",
    "Run Command restores the dump into RDS from inside the VPC. There is no SSH.",
    "Row counts and an MD5 of every row must match on both sides before staff switch over.",
    "Backups and transaction logs replicate to Ireland continuously. S3 replicates every file.",
    "If London fails, one Terraform variable builds Ireland from the same module and restores the database.",
]
y = 146
for i, s_ in enumerate(steps, 1):
    d.badge(i, lx, y, d=20, fs=11)
    d.text(s_, lx + 28, y - 2, 330, 64, fs=12)
    y += 66
d.text("Measured", lx, y + 8, 360, 20, fs=13, bold=True)
res = []
if M.get("cutover"):
    res.append(f"Cutover: {M['cutover']} seconds of frozen writes. Every row and file matched.")
if M.get("rto"):
    res.append(f"Failover drill: serving from Ireland in {mins(M['rto'])}. "
               f"Data lost: {loss(M['rpo'])} of writes, set by backup replication lag.")
d.text("\n".join(res) or "Run the scripts to record results.", lx, y + 32, 360, 90, fs=12)
y += 140
d.text("Legend", lx, y, 360, 20, fs=13, bold=True)
d.text("Grey line: migration and app traffic\nTeal dashed: replication to the DR region\nDashed VPC: built only when failing over",
       lx, y + 24, 360, 70, fs=12, color="#545B64")

open(f"{OUTDIR}/architecture.drawio", "w").write(d.xml())

# =====================================================================
# 2. LinkedIn: 540x675 page, exported at 2x = 1080x1350
# =====================================================================
L = Doc("LinkedIn", 540, 675)
L.add("", "rounded=0;fillColor=#FFFFFF;strokeColor=none;", 0, 0, 540, 675)
L.text("Hybrid migration with disaster recovery", 22, 20, 500, 30, fs=22, bold=True)
L.text("A company server moved to AWS London, recoverable in Ireland.\nBuilt with Terraform.", 22, 52, 500, 40, fs=13,
       color="#545B64")

S = 40
A, B, Cc = 180, 280, 380
loff = L.group("Company office", "office", 16, 104, 508, 104, fs=11)
oapp = L.shape("App", "traditional_server", INK, A + 7, 138, 26, 40, parent=loff, fs=11, pos="right")
odb = L.shape("PostgreSQL", "generic_database", INK, B + 5, 138, 30, 40, parent=loff, fs=11, pos="right")
ofi = L.shape("Files", "documents", INK, Cc + 30, 138, 32, 40, parent=loff, fs=11, pos="right")

lcloud = L.group("AWS Cloud", "cloud", 16, 236, 508, 330, fs=11)
lon = L.group("eu-west-2 (London)", "region", 26, 266, 488, 136, parent=lcloud, fs=11)
ls3 = L.res("Files (S3)", "s3", "storage", A, 302, parent=lon, s=S, fs=11)
lec2 = L.res("App server\n(EC2)", "ec2", "compute", B, 302, parent=lon, s=S, fs=11)
lrds = L.res("Database\n(RDS)", "rds", "database", Cc, 302, parent=lon, s=S, fs=11)

irl = L.group("eu-west-1 (Ireland)", "region", 26, 420, 488, 136, parent=lcloud, fs=11)
rs3 = L.res("Replica files\n(S3)", "s3", "storage", A, 458, parent=irl, s=S, fs=11)
rbk = L.res("Replicated\nbackups (RDS)", "rds", "database", Cc, 458, parent=irl, s=S, fs=11)
L.text("Pilot light. On failover,\nTerraform rebuilds the app\nand restores the database.", B - 50, 452, 140, 54, fs=11,
       color="#545B64", align="center")

L.edge(odb, ls3, "dump and files\nover HTTPS", ex=0.5, ey=1, nx=0.75, ny=0, via=[(B + 15, 222), (A + 30, 222)], fs=10)
L.edge(ls3, lec2)
L.edge(lec2, lrds)
L.edge(ls3, rs3, color=TEAL, dashed=True, ex=0, ey=0.5, nx=0, ny=0.5, via=[(A - 14, 322), (A - 14, 478)])
L.edge(lrds, rbk, color=TEAL, dashed=True, ex=1, ey=0.5, nx=1, ny=0.5, via=[(Cc + S + 14, 322), (Cc + S + 14, 478)])

y = 580
if M.get("cutover"):
    L.text(f"Cutover: {M['cutover']} seconds of frozen writes. Every row and file verified.", 22, y, 500, 18, fs=11)
    y += 18
if M.get("rto"):
    L.text(f"Failover drill: serving from Ireland in {mins(M['rto'])}; {loss(M['rpo'])} of writes lost.", 22, y, 500, 18,
           fs=11)
    y += 18
L.text("github.com/gumagatsby/aws-hybrid-migration-dr", 22, 654, 500, 18, fs=11, color="#545B64")
open(f"{OUTDIR}/linkedin-architecture.drawio", "w").write(L.xml())
print("ok")
