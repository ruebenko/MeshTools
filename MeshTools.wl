(* ::Package:: *)

(* ::Section::Closed:: *)
(*Header comments*)


(* :Title: MeshTools *)
(* :Context: MeshTools` *)
(* :Author: Matevz Pintar *)
(* :Summary: Utilities for generating and manipulating ElementMesh objects. *)
(* :Copyright: C3M d.o.o., Slovenia, 2018 *)

(* :Acknowledgements: Jan Tomec, Joze Korelc, Oliver Ruebenkoenig *)


(* ::Section::Closed:: *)
(*Begin package*)


(* Mathematica FEM functionality (context "NDSolve`FEM`") is needed. *)
BeginPackage["MeshTools`",{"NDSolve`FEM`"}];


(* ::Subsection::Closed:: *)
(*Public symbols*)


AddMeshMarkers;
SelectElementsByMarker;
SelectElements;

MergeMesh;
TransformMesh;
ExtrudeMesh;

SmoothenMesh;
QuadToTriangleMesh;
TriangleToQuadMesh;
HexToTetrahedronMesh;

ElementMeshCurvedWireframe;

MeshElementMeasure;
BoundaryElementMeasure;

StructuredMesh;
RectangleMesh;
TriangleMesh;
DiskMesh;
AnnulusMesh;
CircularVoidMesh;

CuboidMesh;
HexahedronMesh;
TetrahedronMesh;
PrismMesh;
CylinderMesh;
SphereMesh;
SphericalShellMesh;
BallMesh;


(* ::Section::Closed:: *)
(*Code*)


(* Begin private context *)
Begin["`Private`"];


(* ::Subsection::Closed:: *)
(*Mesh operations*)


(* ::Subsubsection::Closed:: *)
(*AddMeshMarkers*)


AddMeshMarkers::usage="AddMeshMarkers[mesh, marker] adds integer marker to all mesh elements.";

AddMeshMarkers//SyntaxInformation={"ArgumentsPattern"->{_,_}};

AddMeshMarkers[mesh_ElementMesh,marker_Integer]:=Module[
	{elementType,head,elementTypes,elementIncidents,elementMarkers},
	
	{elementType,head}=If[
		mesh["MeshElements"]===Automatic,
		{"BoundaryElements",ToBoundaryMesh},
		{"MeshElements",ToElementMesh}
	];
	
	elementTypes=Head/@mesh[elementType];
	elementIncidents=ElementIncidents@mesh[elementType];
	elementMarkers=ConstantArray[marker,#]&/@(Length/@elementIncidents);
	
	head[
		"Coordinates"->mesh["Coordinates"],
		elementType->MapThread[#1[#2,#3]&,{elementTypes,elementIncidents,elementMarkers}]
	]
]


(* ::Subsubsection::Closed:: *)
(*SelectElements*)


SelectElementsByMarker::usage="SelectElementsByMarker[mesh, marker] creates ElementMesh made only out of elements with selected marker.";
SelectElementsByMarker::marker="Specified marker `1` does not exist and unmodified ElementMesh is returned.";

SelectElementsByMarker//SyntaxInformation={"ArgumentsPattern"->{_,_}};

SelectElementsByMarker[mesh_ElementMesh,int_Integer]:=Module[
	{elementType,head,elementHeads,connectivity,markers,selectedElements,selectedNodes,renumbering},
	
	{elementType,head}=If[
		mesh["MeshElements"]===Automatic,
		{"BoundaryElements",ToBoundaryMesh},
		{"MeshElements",ToElementMesh}
	];
	
	elementHeads=Head/@mesh[elementType];
	connectivity=ElementIncidents@mesh[elementType];
	markers=ElementMarkers@mesh[elementType];
	
	If[
		Not@MemberQ[Union@Flatten@markers,int],
		Message[SelectElementsByMarker::marker,int];Return[mesh]
	];
	
	selectedElements=MapThread[Pick[#1,#2,int]&,{connectivity,markers}];
	selectedNodes=Union@Flatten@selectedElements;
	renumbering=MapIndexed[#1->First[#2]&,selectedNodes];

	head[
		"Coordinates" -> Part[mesh["Coordinates"],selectedNodes],
		elementType -> MapThread[#1[#2]&,{elementHeads,selectedElements/.renumbering}]
	]
]


SelectElements::usage="SelectElements[mesh, crit] creates ElementMesh made only out of nodes which match Function crit.";
SelectElements::noelms="No elements in ElementMesh match the criterion.";
SelectElements::funslots="Criterion Function has too many Slots for ElementMesh with \"EmbeddingDimension\"==`1`.";

SelectElements//SyntaxInformation={"ArgumentsPattern"->{_,_}};

SelectElements[mesh_ElementMesh,crit_Function]:=Module[
	{elementType,head,elementHeads,connectivity,markers,renumbering,
	selectedNodes,selectedElementNumbers,selectedElements,selectedMarkers},
	
	(* Test for appropriate number of Slots in crit Function, otherwise problems occur at Apply[crit]... *)
	With[
		{dim=mesh["EmbeddingDimension"]},
		If[ Count[crit,_Slot,Infinity]>dim, Message[SelectElements::funslots,dim];Return[$Failed] ]
	];
	
	{elementType,head}=If[
		mesh["MeshElements"]===Automatic,
		{"BoundaryElements",ToBoundaryMesh},
		{"MeshElements",ToElementMesh}
	];
	
	elementHeads=Head/@mesh[elementType];
	connectivity=ElementIncidents@mesh[elementType];
	markers=ElementMarkers@mesh[elementType];
	
	selectedNodes=MapIndexed[
		If[Apply[crit][#1],First[#2],Nothing]&,
		mesh["Coordinates"]
	];
	renumbering=MapIndexed[#1->First[#2]&,selectedNodes];
	
	selectedElementNumbers=MapIndexed[
		If[ContainsAll[selectedNodes,#1],Last@#2,Nothing]&,
		connectivity,
		{2}
	];
	(* This catches majority of bad crit Function(s), since no elements are selected. *)
	If[
		selectedElementNumbers==={{}},
		Message[SelectElements::noelms];Return[$Failed]
	];
	
	selectedElements=MapThread[Part,{connectivity,selectedElementNumbers}]/.renumbering;
	selectedMarkers=MapThread[Part,{markers,selectedElementNumbers}];

	head[
		"Coordinates" -> Part[mesh["Coordinates"],selectedNodes],
		elementType -> MapThread[#1[#2,#3]&,{elementHeads,selectedElements,selectedMarkers}]
	]
]


(* ::Subsubsection::Closed:: *)
(*TransformMesh*)


(* Helper function to reorder connectivity of elements (TriangleElement, etc.) if 
transformation function has a negative jacobian. *)
transformElements//ClearAll

transformElements[elementObj_List,reorderQ_]:=Map[transformElements[#,reorderQ]&,elementObj]

transformElements[elementObj_,reorderQ_]:=Module[
	{head,connectivity,markers,length,numbering},
	
	head=Head@elementObj;
	connectivity=ElementIncidents@elementObj;
	markers=ElementMarkers@elementObj;
	length=Last@Dimensions[connectivity];
	(* Common renumbering for 1st and 2nd order. *)
	numbering=Take[
		head/.{
			TriangleElement->{2,1,3,4,6,5},
			QuadElement->{2,1,4,3,5,8,7,6},
			TetrahedronElement->{3,2,1,4,6,5,7,8,10,9},
			HexahedronElement->{2,1,4,3,6,5,8,7,9,12,11,10,13,16,15,14,18,17,20,19},
			LineElement->{2,1,3},
			PointElement->{1}
			},
		length
	];
	
	If[
		TrueQ[reorderQ],
		head[connectivity[[All,numbering]],markers],
		head[connectivity,markers]
	]
]


TransformMesh::usage="TransformMesh[mesh, tfun] transforms ElementMesh mesh according to TransformationFunction tfun";

TransformMesh//Options=Options@ElementMesh;

TransformMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,OptionsPattern[]}};

TransformMesh[mesh_ElementMesh,tfun_TransformationFunction,opts:OptionsPattern[]]:=Module[
	{reorderQ},
	
	(* If TransformationFunction represents reflection (or inversion), 
	then element incidents have to be reordered. *)
	reorderQ=Negative@Det[TransformationMatrix[tfun]];
	
	If[
		mesh["MeshElements"]===Automatic,
		ToBoundaryMesh[
			"Coordinates"->tfun/@mesh["Coordinates"],
			"BoundaryElements"->transformElements[mesh["BoundaryElements"],reorderQ],
			"PointElements"->transformElements[mesh["PointElements"],reorderQ],
			FilterRules[{opts},Options@ElementMesh]
		],
		ToElementMesh[
			"Coordinates"->tfun/@mesh["Coordinates"],
			"MeshElements"->transformElements[mesh["MeshElements"],reorderQ],
			"BoundaryElements"->transformElements[mesh["BoundaryElements"],reorderQ],
			"PointElements"->transformElements[mesh["PointElements"],reorderQ],
			FilterRules[{opts},Options@ElementMesh]
		]
	]
]


(* ::Subsubsection::Closed:: *)
(*MergeMesh*)


(* 
Code is adjusted after this source: 
https://mathematica.stackexchange.com/questions/156445/automatically-generating-boundary-meshes-for-region-intersections 
*)
MergeMesh::usage="MergeMesh[{mesh1,mesh2,...}] merges a list of ElementMesh objects with the same embedding dimension.";
MergeMesh::order="Meshes must have the same \"MeshOrder\".";
MergeMesh::dim="Meshes must have the same \"EmbeddingDimension\".";

MergeMesh//Options=Options@ElementMesh;

MergeMesh//SyntaxInformation={"ArgumentsPattern"->{_,OptionsPattern[]}};

MergeMesh[list_List/;Length[list]>=2,opts:OptionsPattern[]]:=Fold[MergeMesh[#1,#2,opts]&,list]

MergeMesh[mesh1_ElementMesh,mesh2_ElementMesh,opts:OptionsPattern[]]:=Module[
	{elementType,head,c1,c2,newCrds,newElements,elementTypes,elementMarkers,inci1,inci2},
	
	If[
		mesh1["MeshOrder"]=!=mesh2["MeshOrder"],
		Message[MergeMesh::order];Return[$Failed]
	];
	If[
		mesh1["EmbeddingDimension"]=!=mesh2["EmbeddingDimension"],
		Message[MergeMesh::dim];Return[$Failed]
	];
		
	{elementType,head}=If[
		mesh1["MeshElements"]===Automatic,
		{"BoundaryElements",ToBoundaryMesh},
		{"MeshElements",ToElementMesh}
	];
	
	c1=mesh1["Coordinates"];
	c2=mesh2["Coordinates"];
	newCrds=Join[c1,c2];
	elementTypes=Join[Head/@mesh1[elementType],Head/@mesh2[elementType]];
	elementMarkers=ElementMarkers/@{mesh1[elementType],mesh2[elementType]};
	
	inci1=ElementIncidents[mesh1[elementType]];
	inci2=ElementIncidents[mesh2[elementType]]+Length[c1];
	(* If all elements are of the same type, then this type is specified only once. *)
	newElements=If[
		SameQ@@elementTypes,
		{First[elementTypes][Join[Join@@inci1,Join@@inci2],Flatten[elementMarkers]]},
		MapThread[#1[#2,#3]&,{elementTypes,Join[inci1,inci2],Join@@elementMarkers}]
	];
	
	head[
		"Coordinates"->newCrds,
		elementType->newElements,
		FilterRules[{opts},Options@ElementMesh]
	]
]


(* ::Subsubsection::Closed:: *)
(*ExtrudeMesh*)


ExtrudeMesh::usage="ExtrudeMesh[mesh, thickness, layers] extrudes 2D quadrilateral mesh to 3D hexahedron mesh.";
ExtrudeMesh::badType="Only first order 2D quadrilateral mesh is supported.";

ExtrudeMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,_}};

(* TODO: Should argument checking be done inside the function? *)
ExtrudeMesh[mesh_ElementMesh,thickness_?Positive,layers_Integer?Positive]:=Module[
	{n,nodes2D,nodes3D,elements2D,elements3D,markers2D,markers3D},
	
	If[
		Or[mesh["MeshOrder"]=!=1,(Head/@mesh["MeshElements"])=!={QuadElement},mesh["EmbeddingDimension"]=!=2],
		Message[ExtrudeMesh::badType];Return[$Failed]
	];
		
	nodes2D=mesh["Coordinates"];
	elements2D=Join@@ElementIncidents[mesh["MeshElements"]];
	markers2D=Join@@ElementMarkers[mesh["MeshElements"]];
	n=Length[nodes2D];
	
	nodes3D=Join@@Map[
		(Transpose@Join[Transpose[nodes2D],{ConstantArray[#,n]}])&,
		Subdivide[0.,thickness,layers]
	];

	elements3D=Join@@Table[
		Map[Join[n*(i-1)+#,n*i+#]&,elements2D],
		{i,layers}
	];

	markers3D=Flatten@ConstantArray[markers2D,layers];
	
	ToElementMesh[
		"Coordinates"->nodes3D,
		"MeshElements"->{HexahedronElement[elements3D,markers3D]}
	]
]


(* ::Subsubsection::Closed:: *)
(*Mesh smoothing*)


(* 
This implements Laplacian mesh smoothing method as described in 
https://mathematica.stackexchange.com/a/156669 
*)
SmoothenMesh::usage="SmoothenMesh[mesh] improves the quality of 2D mesh.";
SmoothenMesh::badType="Smoothing is only supported for first order 2D meshes.";

SmoothenMesh//SyntaxInformation={"ArgumentsPattern"->{_}};

SmoothenMesh[mesh_ElementMesh]:=Block[
	{n,vec,mat,adjacencymatrix2,mass2,laplacian2,bndvertices2,interiorvertices,stiffness,load,newCoords},
	
	If[
		Or[mesh["MeshOrder"]=!=1,mesh["EmbeddingDimension"]=!=2],
		Message[SmoothenMesh::badType];Return[$Failed]
	];
	
	n=Length[mesh["Coordinates"]];
	vec=mesh["VertexElementConnectivity"];
	mat=Unitize[vec.Transpose[vec]];
	vec=Null;
	adjacencymatrix2=mat-DiagonalMatrix[Diagonal[mat]];
	mass2=DiagonalMatrix[SparseArray[Total[adjacencymatrix2,{2}]]];
	stiffness=N[mass2-adjacencymatrix2];
	adjacencymatrix2=Null;
	mass2=Null;
	bndvertices2=Flatten[Join@@ElementIncidents[mesh["PointElements"]]];
	interiorvertices=Complement[Range[1,n],bndvertices2];
	stiffness[[bndvertices2]]=IdentityMatrix[n,SparseArray][[bndvertices2]];
	load=ConstantArray[0.,{n,mesh["EmbeddingDimension"]}];
	load[[bndvertices2]]=mesh["Coordinates"][[bndvertices2]];
	newCoords=LinearSolve[stiffness,load(*,Method\[Rule]"Pardiso"*)];
	
	ToElementMesh[
		"Coordinates"->newCoords,
		"MeshElements"->mesh["MeshElements"],
		"BoundaryElements"->mesh["BoundaryElements"],
		"PointElements"->mesh["PointElements"],
		"CheckIncidentsCompletness"->False,
		"CheckIntersections"->False,
		"DeleteDuplicateCoordinates"->False
	]
]


(* ::Subsubsection::Closed:: *)
(*QuadToTriangleMesh*)


(* TODO: Add "smart" method of splitting triangles, where diagonal is chosen according to better quality of
 resulting triangle. *)
QuadToTriangleMesh::usage="QuadToTriangleMesh[mesh] converts quadrilateral mesh to triangular mesh.";
QuadToTriangleMesh::order="Only the first order mesh is currently supported.";

QuadToTriangleMesh//SyntaxInformation={"ArgumentsPattern"->{_}};

QuadToTriangleMesh[mesh_ElementMesh]:=Module[{
	elementType,head,connectivity,triangles
	},
	If[mesh["MeshOrder"]=!=1,Message[QuadToTriangleMesh::order];Return[$Failed]];
	
	{elementType,head}=If[
		mesh["MeshElements"]===Automatic,
		{"BoundaryElements",ToBoundaryMesh},
		{"MeshElements",ToElementMesh}
	];
	
	connectivity=ElementIncidents@First@mesh[elementType];
	triangles=Join[connectivity[[All,{1,2,3}]],connectivity[[All,{1,3,4}]]];
	
	head[
		"Coordinates"->mesh["Coordinates"],
		elementType->{TriangleElement[triangles]}
	]
]


(* ::Subsubsection::Closed:: *)
(*HexToTetrahedronMesh*)


HexToTetrahedronMesh::usage="HexToTetrahedronMesh[mesh] converts hexahedral mesh to tetrahedral mesh.";
HexToTetrahedronMesh::type="ElementMesh should contain only hexadedral elements.";

HexToTetrahedronMesh//SyntaxInformation={"ArgumentsPattern"->{_}};
(* TODO: Figure out if this function actually works correctly. *)
HexToTetrahedronMesh[mesh_ElementMesh]:=Module[
	{nodes,origElms,tetConnect,restructure,newElms},
	
	origElms=mesh["MeshElements"];
	If[
		Head@First[origElms]=!=HexahedronElement,
		Message[HexToTetrahedronMesh::type];Return[$Failed]
	];
	
	tetConnect={
		{4, 1, 2, 5},
		{7, 5, 2, 6},
		{4, 2, 3, 7},
		{4, 5, 2, 7},
		{4, 5, 7, 8}
	};
	restructure=Function[{hexNodes},Part[hexNodes,#]&/@tetConnect];
	
	newElms=TetrahedronElement[
		Flatten[restructure/@First@ElementIncidents[origElms],1]
	];
	
	ToElementMesh[
		"Coordinates"->mesh["Coordinates"],
		"MeshElements"->{newElms}
	]
]


(* ::Subsubsection::Closed:: *)
(*TriangleToQuadMesh*)


distortion:=distortion=Compile[
	{{n1, _Real, 1}, {n2, _Real, 1}, {n3, _Real, 1}, {n4, _Real, 1}},
	2/Pi * Max @ Map[
		Abs[Pi/2 - If[ # < 0, Pi - #, #] ]& @ 
			ArcTan[#[[1, 1]] #[[2, 1]] + #[[1, 2]] #[[2, 2]],
					#[[1, 1]] #[[2, 2]] - #[[1, 2]] #[[2, 1]]
				]&,
		{{n2-n1, n4-n1}, {n3-n2, n1-n2}, {n4-n3, n2-n3}, {n1-n4, n3-n4}}
	]
];


(*
Source of algorithm for mesh conversion is:
	Houman Borouchaki, Pascal J. Frey;
	Adaptive triangular\[Dash]quadrilateral mesh generation;
	International Journal for Numerical Methods in Engineering;
	1998; Vol. 41, p. (915-934)

Original implementation is by Prof. Joze Korelc taken from AceFEM package 
(http://symech.fgg.uni-lj.si/). Layout of function and other properties
have been improved by Oliver Ruebenkoenig from WRI.
*)
TriangleToQuadMesh::usage="TriangleToQuadMesh[mesh] converts triangular mesh to quadrilateral mesh.";
TriangleToQuadMesh::elmtype = "Only conversion of pure triangular meshes is supported."

TriangleToQuadMesh//SyntaxInformation={"ArgumentsPattern"->{_}};

TriangleToQuadMesh[meshIn_] /; ElementMeshQ[meshIn] && !BoundaryElementMeshQ[meshIn] &&
	meshIn["EmbeddingDimension"] === 2 := Module[
	{coor, econn, elem, dist, ncoor, taken, quad, triag, edge, nc, allquads, 
	alltriag, marker, nodes, markerQ, mesh, increaseOrderQ},

	mesh = meshIn;
	
	If[
		mesh["MeshOrder"] =!= 1,
		mesh = MeshOrderAlteration[mesh, 1]
	];
		increaseOrderQ = True;

	If[ Union[Head /@ mesh["MeshElements"]] =!= {TriangleElement},
		Message[TriangleToQuadMesh::elmtype]; Return[$Failed, Module]
	];

	coor = mesh["Coordinates"];
	econn = Join @@ mesh["ElementConnectivity"];
	(* zero is used as a default marker *)
	marker = Join @@ ElementMarkers[ mesh["MeshElements"]];
	markerQ = ElementMarkersQ[mesh["MeshElements"]];
	elem = Join @@ ElementIncidents[ mesh["MeshElements"]];	
	
	dist = MapThread[ (
		{
		If[ #2[[1]] == 0,
			Nothing,
			distortion[Sequence@@coor[[nodes = {#[[1]], #[[2]], Complement[elem[[#2[[1]]]], #1][[1]], #[[3]]}]]]->{#3, #2[[1]], nodes}
		],
		If[ #2[[2]] == 0,
			Nothing,
			distortion[Sequence@@coor[[nodes = {#[[1]], #[[2]], #[[3]], Complement[elem[[#2[[2]]]], #1][[1]]}]]]->{#3, #2[[2]], nodes}
		],
		If[ #2[[3]] == 0,
			Nothing,
			distortion[Sequence@@coor[[nodes = {#[[1]], Complement[elem[[#2[[3]]]], #1][[1]], #[[2]], #[[3]]}]]]->{#3, #2[[3]], nodes}
		]
		})&,
		{elem, econn, Range[elem//Length]}
	]//Flatten;

	taken = ConstantArray[False, elem//Length];
	quad = Map[
		If[ 
			Or@@taken[[#[[2, {1, 2}]]]]  || #[[1]]>0.8 || marker[[#[[2, 1]]]]  =!= marker[[#[[2, 2]]]],
			Nothing,
			taken[[#[[2, {1, 2}]]]] = True;{#[[2, 3]], marker[[#[[2, 1]]]]}
		]&,
		Sort[dist]
	]//Transpose;
	
	dist = Null;
	triag = {Extract[elem, #], Extract[marker, #]}& @ Position[taken, False];
	edge = DeleteDuplicates[
		Join[
			Flatten[Map[{#[[{1, 2}]]//Sort, #[[{2, 3}]]//Sort, #[[{3, 4}]]//Sort, #[[{4, 1}]]//Sort} &, quad[[1]]], 1],
			Flatten[Map[{#[[{1, 2}]]//Sort, #[[{2, 3}]]//Sort, #[[{3, 1}]]//Sort} &, triag[[1]]], 1]
		]
	];
	
	ncoor = coor//Length;
	nc = Dispatch[Flatten[Map[(ncoor++;{#->ncoor, #[[{2, 1}]]->ncoor})&, edge]]];
	
	allquads = MapThread[
		(ncoor++; 
		{Total[coor[[#]]]/4,
			{
			{#[[1]], #[[{1, 2}]]/.nc, ncoor, #[[{4, 1}]]/.nc},
			{#[[{1, 2}]]/.nc, #[[2]], #[[{2, 3}]]/.nc, ncoor},
			{ncoor, #[[{2, 3}]]/.nc, #[[3]], #[[{3, 4}]]/.nc},
			{#[[{4, 1}]]/.nc, ncoor, #[[{3, 4}]]/.nc, #[[4]]}
			},
		{#2, #2, #2, #2}
		})& ,
		quad
	];
	
	alltriag = MapThread[
		(ncoor++;
		{Total[coor[[#]]]/3,
			{
			{#[[1]], #[[{1, 2}]]/.nc, ncoor, #[[{3, 1}]]/.nc},
			{#[[{1, 2}]]/.nc, #[[2]], #[[{2, 3}]]/.nc, ncoor},
			{ncoor, #[[{2, 3}]]/.nc, #[[3]], #[[{3, 1}]]/.nc}
			},
		{#2, #2, #2}})&, 
		triag
	];

	mesh = ToElementMesh[
				"Coordinates" -> Join[
					coor,
					Map[(coor[[#[[1]]]]+coor[[#[[2]]]])/2&, edge],
					allquads[[All, 1]], alltriag[[All, 1]]
				], 
				"MeshElements" -> If[ markerQ,
					{QuadElement[Flatten[Join[
						allquads[[All, 2]],
						alltriag[[All, 2]]], 1],
						Flatten[{allquads[[All, 3]], alltriag[[All, 3]]}]]},
					{QuadElement[Flatten[Join[
						allquads[[All, 2]], alltriag[[All, 2]]], 1]]}
				],
				"RegionHoles" -> meshIn["RegionHoles"]
			];

	If[ !ElementMeshQ[mesh], Return[ $Failed, Module]];

	If[ increaseOrderQ, mesh = MeshOrderAlteration[mesh, meshIn["MeshOrder"]]];

	mesh
]


(* ::Subsection::Closed:: *)
(*Mesh measurements*)


(* ::Subsubsection::Closed:: *)
(*MeshElementMeasure*)


elementMeasure//ClearAll

(* Definition for multiple elements in a list. *)
elementMeasure[nodes_List/;(Depth[nodes]==4),type_,order_]:=elementMeasure[#,type,order]&/@nodes

(* Length of LineElement (as "MeshElement") is calculated differently. *)
elementMeasure[nodes_List/;(Depth[nodes]==3),LineElement,order_]:=Abs[Differences@Flatten@Take[nodes,2]]

elementMeasure[nodes_List/;(Depth[nodes]==3),type_,order_]:=Block[{
	igCrds=ElementIntegrationPoints[type,order],
	igWgts=ElementIntegrationWeights[type,order],
	shapeDerivative=ElementShapeFunctionDerivative[type,order],
	jacobian,r,s,t
	},
	
	jacobian=With[{
		vars=(type/.{
			TriangleElement|QuadElement->{r,s},
			TetrahedronElement|HexahedronElement->{r,s,t}
		})
		},
		Function[Evaluate@vars,Evaluate@Det[(shapeDerivative@@vars).nodes]]
	];
	
	(jacobian@@@igCrds).igWgts
]


(* This function gives the same result as asking for the property mesh["MeshElementMeasure"] *)
MeshElementMeasure::usage="MeshElementMeasure[mesh] gives the measure of each mesh element.";

MeshElementMeasure//SyntaxInformation={"ArgumentsPattern"->{_}};

MeshElementMeasure[mesh_ElementMesh]:=Module[
	{order,elements,nodes,elementCoordinates,elementTypes},
	
	order=mesh["MeshOrder"];
	elements=mesh["MeshElements"];
	nodes=mesh["Coordinates"];
	elementCoordinates=Map[Part[nodes,#]&,ElementIncidents@elements,{2}];
	elementTypes=Head/@elements;
	
	MapThread[
		elementMeasure[#1,#2,order]&,
		{elementCoordinates,elementTypes}
	]
]


(* ::Subsubsection::Closed:: *)
(*BoundaryElementMeasure*)


boundaryElementMeasure//ClearAll

(* Boundary mesh measure for each submesh. *)
boundaryElementMeasure[
	nodes_List/;(Depth[nodes]==4),
	type_,
	order_,
	integrationOrder_]:=
	boundaryElementMeasure[#,type,order,integrationOrder]&/@nodes

(* Boundary mesh measure for each 1D element. *)
boundaryElementMeasure[
	nodes_List/;(Depth[nodes]==3),
	type_/;(type==LineElement),
	order_,
	integrationOrder_]:=Block[{
		f,\[Xi],
		igCrds=ElementIntegrationPoints[type,integrationOrder],
		igWgts=ElementIntegrationWeights[type,integrationOrder]
		},
		f=Function[{\[Xi]},Cross@@(ElementShapeFunctionDerivative[type,order][\[Xi]].nodes//Simplify )//Norm];
		igWgts.(f@@@igCrds)
]

(* Boundary mesh measure for each 2D element. *)
boundaryElementMeasure[
	nodes_List/;(Depth[nodes]==3),
	type_,
	order_,
	integrationOrder_]:=Block[{
		f,\[Xi],\[Eta],
		igCrds=ElementIntegrationPoints[type,integrationOrder],
		igWgts=ElementIntegrationWeights[type,integrationOrder]
		},
		f=Function[{\[Xi],\[Eta]},Cross@@(ElementShapeFunctionDerivative[type,order][\[Xi],\[Eta]].nodes//Simplify )//Norm];
		igWgts.(f@@@igCrds)
]


(* This function returns the surface of boundary elements in 3D embedding and length of 
boundary elements in 2D embedding. *)
BoundaryElementMeasure::usage="BoundaryElementMeasure[mesh] gives the measure of each boundary element.";

BoundaryElementMeasure//SyntaxInformation={"ArgumentsPattern"->{_}};

BoundaryElementMeasure[mesh_ElementMesh]:=Module[
	{order,elements,nodes,elementCoordinates,elementTypes},
	
	order=mesh["MeshOrder"];
	elements=mesh["BoundaryElements"];
	nodes=mesh["Coordinates"];
	elementCoordinates=Map[Part[nodes,#]&,ElementIncidents@elements,{2}];
	elementTypes=Head/@mesh["BoundaryElements"];
	
	MapThread[
		boundaryElementMeasure[#1,#2,order,3]&,
		{elementCoordinates,elementTypes}
	]
]


(* ::Subsection::Closed:: *)
(*Mesh visualization*)


(* 
Function to visualize 2D second order FEM mesh. 
Copied from: WTC 2017 talk "Finite Element Method: How to talk to it and make it your friend" by Paritosh Mokhasi 
*)
ElementMeshCurvedWireframe::usage="ElementMeshCurvedWireframe[mesh] plots second order mesh with curved edges.";

ElementMeshCurvedWireframe//SyntaxInformation={"ArgumentsPattern"->{_}};

ElementMeshCurvedWireframe[mesh_ElementMesh]:=Block[
	{triIncidentsOrder,quadIncidentsOrder,interpolatingQuadBezierCurve,interpolatingQuadBezierCurveComplex,
	triEdges,triIncidents,coordinates},

	triIncidentsOrder={1,4,2,5,3,6};
	quadIncidentsOrder={1,5,2,6,3,7,4,8};

	interpolatingQuadBezierCurve[pts_List]/;Length[pts]==3:=
		BezierCurve[{pts[[1]],(1/2)(-pts[[1]]+4 pts[[2]]-pts[[3]]),pts[[3]]}];
	interpolatingQuadBezierCurve[pts_List,"ControlPoints"]/;(Length[pts]==3):=
		{pts[[1]],(1/2)(-pts[[1]]+4 pts[[2]]-pts[[3]]),pts[[3]]};
	interpolatingQuadBezierCurve[ptslist_List]:=interpolatingQuadBezierCurve/@ptslist;

	interpolatingQuadBezierCurveComplex[coords_,indices_]:=interpolatingQuadBezierCurve[Map[coords[[#]]&,indices]];

	triEdges=Partition[triIncidentsOrder, 3, 2, {1,1}];
	triIncidents=Join@@ElementIncidents[mesh["MeshElements"]];
	coordinates=mesh["Coordinates"];
	
	Graphics[{
		interpolatingQuadBezierCurveComplex[coordinates,triIncidents[[All, #]]]&/@triEdges
	}]
]


(* ::Subsection::Closed:: *)
(*Structured mesh*)


getElementConnectivity[nx_,ny_]:=Flatten[
	Table[{
		i+(j-1)(nx+1),
		i+(j-1)(nx+1)+1,
		i+j(nx+1)+1,
		i+j(nx+1)
		},
		{j,1,ny},
        {i,1,nx}
   ],
   1
]

(* =====================================================================\[Equal] *)

getElementConnectivity[nx_,ny_,nz_]:=Flatten[
	Table[{
		i+(j-1)(nx+1)+(k-1)(nx+1)(ny+1),
		i+(j-1)(nx+1)+(k-1)(nx+1)(ny+1)+1,
		i+j(nx+1)+(k-1)(nx+1)(ny+1)+1,
		i+j(nx+1)+(k-1)(nx+1)(ny+1),
		i+(j-1)(nx+1)+k(nx+1)(ny+1),
		i+(j-1)(nx+1)+k(nx+1)(ny+1)+1,
		i+j(nx+1)+k(nx+1)(ny+1)+1,
		i+j(nx+1)+k(nx+1)(ny+1)
        },
        {k,1,nz},
        {j,1,ny},
        {i,1,nx}
    ],
    2
]


(* This function may cause shadowing with the same function in FEMAddOns paclet (https://github.com/WolframResearch/FEMAddOns). *)

StructuredMesh::usage=(
	"StructuredMesh[raster,{nx,ny}] creates structured mesh of quadrilaterals."<>"\n"<>
	"StructuredMesh[raster,{nx,ny,nz}] creates structured mesh of hexahedra."
);
StructuredMesh::array="Raster of input points must be full array of numbers with depth of `1`.";

StructuredMesh//Options={InterpolationOrder->1};

StructuredMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,OptionsPattern[]}};

StructuredMesh[raster_,{nx_,ny_},opts:OptionsPattern[]]:=Module[
	{order,dim,restructured,xInt,yInt,zInt,nodes,connectivity},
	
	If[
		Not@ArrayQ[raster,3,NumericQ],
		Message[StructuredMesh::array,3+1];Return[$Failed]
    ];

    order=OptionValue[InterpolationOrder]/.Automatic->1;
    dim=Last@Dimensions[raster];

    restructured=Transpose[raster,{3,2,1}];
    xInt=ListInterpolation[restructured[[1]],{{0,1},{0,1}},InterpolationOrder->order];
    yInt=ListInterpolation[restructured[[2]],{{0,1},{0,1}},InterpolationOrder->order];

    nodes=Join@@If[dim==3,
        zInt=ListInterpolation[restructured[[3]],{{0,1},{0,1}},InterpolationOrder->order];
        Table[{xInt[i,j],yInt[i,j],zInt[i,j]},{j,0,1,1./ny},{i,0,1,1./nx}]
        ,
        Table[{xInt[i,j],yInt[i,j]},{j,0,1,1./ny},{i,0,1,1./nx}]
    ];

    connectivity=getElementConnectivity[nx,ny];

    If[dim==3,
        ToBoundaryMesh["Coordinates"->nodes,"BoundaryElements"->{QuadElement[connectivity]}],
        ToElementMesh["Coordinates"->nodes,"MeshElements"->{QuadElement[connectivity]}]
    ]
]

(* ===================================================================================== *)

StructuredMesh[raster_,{nx_,ny_,nz_},opts:OptionsPattern[]]:=Module[
	{order,restructured,xInt,yInt,zInt,nodes,connectivity},
	
	If[
		Not@ArrayQ[raster,4,NumericQ],
		Message[StructuredMesh::array,4+1];Return[$Failed]
	];

    order=OptionValue[InterpolationOrder]/.Automatic->1;
       
    restructured=Transpose[raster,{4, 3, 2, 1}];
    xInt=ListInterpolation[restructured[[1]],{{0,1},{0,1},{0,1}},InterpolationOrder->order];
    yInt=ListInterpolation[restructured[[2]],{{0,1},{0,1},{0,1}},InterpolationOrder->order];
    zInt=ListInterpolation[restructured[[3]],{{0,1},{0,1},{0,1}},InterpolationOrder->order];
    
    nodes=Flatten[
       Table[
          {xInt[i,j,k],yInt[i,j,k],zInt[i,j,k]},
          {k,0,1,1./nz},{j,0,1,1./ny},{i,0,1,1./nx}
       ],
       2
    ];

    connectivity=getElementConnectivity[nx,ny,nz];
    
    ToElementMesh["Coordinates"->nodes,"MeshElements"->{HexahedronElement[connectivity]}]
]


(* ::Subsection::Closed:: *)
(*Named meshes 2D*)


(* ::Subsubsection::Closed:: *)
(*Helper functions for Simplex*)


(* Adjusted from documentation page on Triangle and Tetrahedron *)
symmetricSubdivision[shape_[pl_],k_]/;0<=k<2^Length[pl]:=Module[
	{n=Length[pl]-1,i0,bl,pos},
	
	i0=DigitCount[k,2,1]; 
	bl=IntegerDigits[k,2,n];
	pos=FoldList[If[#2==0,#1+{0,1},#1+{1,0}]&,{0,i0},Reverse[bl]];
	shape@Map[Mean,Extract[pl,#]&/@Map[{#}&,pos+1,{2}]] 
]


(* Adjusted from documentation page on Triangle and Tetrahedron *)
nestedSymmetricSubdivision[shape_[pl_],level_Integer]/;level==0:=shape[pl]

nestedSymmetricSubdivision[shape_[pl_],level_Integer]/;level>0:=Flatten[
	Map[
		nestedSymmetricSubdivision[symmetricSubdivision[shape[pl],#],level-1]&,
		Range[0,(shape/.{Triangle->3,Tetrahedron->7})]
	]
]


(* Helper function to check the orientation of nodes used in TriangleElement and TetrahedronElement*)
reorientSimplex[{a_,b_,c_}]:=If[
	Negative@Det[{a-c,b-c}],
	{a,c,b},
	{a,b,c}
]

reorientSimplex[{a_,b_,c_,d_}]:=If[
	Positive@Det[{a-d,b-d,c-d}],
	{a,b,d,c},
	{a,b,c,d}
]


(* TODO: It would be really nice if Triangle and Tetrahedron could be split to arbitrary 
number of elements per edge.*)

simplexMesh[shape_,corners_,n_Integer]:=Module[
	{divisions,f,allCrds,nodes,connectivity,elementType},
	
	elementType=shape/.{Triangle->TriangleElement,Tetrahedron->TetrahedronElement};
	divisions=Log[2,n];
	
	allCrds=reorientSimplex/@(Join@@List@@@nestedSymmetricSubdivision[shape[corners],divisions]);
	nodes=DeleteDuplicates@Flatten[allCrds,1];
	connectivity=With[
		{rules=Thread[nodes->Range@Length[nodes]]},
		Replace[allCrds,rules,{2}]
	];
	
	ToElementMesh[
		"Coordinates"->nodes,
		"MeshElements"->{elementType[connectivity]}
	]
]


(* ::Subsubsection::Closed:: *)
(*RectangleMesh*)


RectangleMesh::usage="RectangleMesh[{xMin, yMin},{xMax, yMax},{nx, ny}] creates structured mesh on axis-aligned Rectangle with corners {xMin,yMin} and {xMax,yMax}.";

RectangleMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,_}};

RectangleMesh[n_Integer]:=RectangleMesh[{0,0},{1,1},{n,n}]

RectangleMesh[{x1_,y1_},{x2_,y2_},{nx_Integer,ny_Integer}]:=StructuredMesh[
	{{{x1,y1},{x2,y1}},{{x1,y2},{x2,y2}}},
	{nx,ny}
]


(* ::Subsubsection::Closed:: *)
(*TriangleMesh*)


splitTriangleToQuads[{p1_,p2_,p3_},n_Integer]:=Module[
	{n1,n2,n3,x,connectivity},
	
	(* Renumber triangle to be consistent with TriangleElement *)
	{n1,n2,n3}=reorientSimplex[{p1,p2,p3}];
	
	x=Join[{n1,n2,n3},Mean/@{{n1,n2},{n2,n3},{n3,n1},{n1,n2,n3}}];
	connectivity={
		{{x[[1]],x[[4]]},{x[[6]],x[[7]]}},
		{{x[[4]],x[[2]]},{x[[7]],x[[5]]}},
		{{x[[6]],x[[7]]},{x[[3]],x[[5]]}}
	};
	MergeMesh@Map[
		StructuredMesh[#,{n,n}]&,
		connectivity
	]
]


TriangleMesh::usage="TriangleMesh[{p1, p2, p3}, n] creates triangular mesh on Triangle with corners p1, p2 and p3.";
TriangleMesh::trielms="Only 2, 4, 8, 16 or 32 elements per edge are supported for \"MeshElementType\"->TriangleElement.";
TriangleMesh::quadelms="Only even number of elements per edge is allowed for \"MeshElementType\"->QuadElement.";
TriangleMesh::badtype="Unknown option value for \"MeshElementType\"->`1`.";

TriangleMesh//Options={"MeshElementType"->QuadElement};

TriangleMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,OptionsPattern[]}};

TriangleMesh[n_Integer,opts:OptionsPattern[]]:=TriangleMesh[{{0,0},{1,0},{0,1}},n,opts]

TriangleMesh[{p1_,p2_,p3_},n_Integer,opts:OptionsPattern[]]:=Module[
	{type},
	
	type=OptionValue["MeshElementType"];
	
	If[
		(type===TriangleElement)&&Not@MemberQ[{2,4,8,16,32},n],
		Message[TriangleMesh::trielms];Return[$Failed]
	];
	
	If[
		(type===QuadElement)&&OddQ[n],
		Message[TriangleMesh::quadelms];Return[$Failed]
	];
	
	Switch[type,
		TriangleElement,simplexMesh[Triangle,{p1,p2,p3},n],
		QuadElement,splitTriangleToQuads[{p1,p2,p3},n/2],
		_,Message[TriangleMesh::badtype,type];$Failed
	]
]


(* ::Subsubsection::Closed:: *)
(*DiskMesh*)


diskMeshProjection[{x_,y_},r_,n_Integer/;(n>=2)]:=Module[
	{square,rescale,coordinates},
	
	rescale=(Max[Abs@#]*Normalize[#])&;
	(* This special raster makes all element edges on disk edge of the same length. *)
	square=With[
		{pts=r*N@Tan@Subdivide[-Pi/4,Pi/4,n]},
		StructuredMesh[Outer[Reverse@*List,pts,pts],{n,n}]
	];
	
	coordinates=Transpose[Transpose[rescale/@square["Coordinates"]]+{x,y}];
	
	ToElementMesh[
		"Coordinates" ->coordinates,
		"MeshElements" -> square["MeshElements"]
	]
]


diskMeshBlock[{x_,y_},r_,n_Integer/;(n>=2)]:=Module[
	{square,sideMesh,d,raster,rotations},
	
	(* Size of internal square. Optimial minimal element quality is obtained at 0.2.
	Value of 0.3 creates nicer element size distribution. *)
	d=0.3*r;
	square=RectangleMesh[{x-d,y-d},{x+d,y+d},{n,n}];

	raster={
		Thread[{x+Subdivide[-d,d,90],y+d}],
		N@Table[{x+r*Cos[fi],y+r*Sin[fi]},{fi,3Pi/4,Pi/4,-Pi/180}]
	};
	sideMesh=StructuredMesh[raster,{n,n}];
	rotations=RotationTransform[#,{x,y}]&/@(Range[4]*Pi/2);
	
	MergeMesh@Join[{square},TransformMesh[sideMesh,#]&/@rotations]	
]


DiskMesh::usage="DiskMesh[{x, y}, r, n] creates structured mesh with n elements on Disk of radius r centered at {x,y}.";
DiskMesh::method="Method \"`1`\" is not supported.";
DiskMesh::noelems="Specificaton of elements `1` must be an integer equal or larger than 2.";

DiskMesh//Options={Method->Automatic};

DiskMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,_,OptionsPattern[]}};

DiskMesh[n_Integer,opts:OptionsPattern[]]:=DiskMesh[{0,0},1,n,opts]

DiskMesh[{x_,y_},r_,n_Integer,opts:OptionsPattern[]]:=Module[
	{method},
	
	If[
		Not@TrueQ[n>=2&&IntegerQ[n]],
		Message[DiskMesh::noelems,n];Return[$Failed]
	];
	
	method=OptionValue[Method]/.Automatic->"Block";
		
	Switch[method,
		"Block",diskMeshBlock[{x,y},r,n],
		"Projection",diskMeshProjection[{x,y},r,n],
		_,Message[DiskMesh::method,method];Return[$Failed]
	]
]


(* ::Subsubsection::Closed:: *)
(*AnnulusMesh*)


AnnulusMesh::usage=
	"AnnulusMesh[{x, y}, {rIn, rOut}, {n\[Phi], nr}] creates mesh on Annulus with n\[Phi] elements in circumferential and nr elements in radial direction."<>"\n"<>
	"AnnulusMesh[{x, y}, {rIn, rOut}, {\[Phi]1, \[Phi]2}, {n\[Phi], nr}] creates mesh on Annulus from angle \[Phi]1 to \[Phi]2.";

AnnulusMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,_,_.}};

AnnulusMesh[{n\[Phi]_Integer,nr_Integer}]:=AnnulusMesh[{0,0},{1/2,1},{0,2Pi},{n\[Phi],nr}]

AnnulusMesh[{x_,y_},{rIn_,rOut_},{n\[Phi]_Integer,nr_Integer}]:=AnnulusMesh[{x,y},{rIn,rOut},{0,2Pi},{n\[Phi],nr}]

AnnulusMesh[{x_,y_},{rIn_,rOut_},{\[Phi]1_,\[Phi]2_},{n\[Phi]_Integer,nr_Integer}]:=Module[
	{raster},
	raster=N@{
		Table[rOut*{Cos[fi],Sin[fi]}+{x,y},{fi,\[Phi]1,\[Phi]2,(\[Phi]2-\[Phi]1)/n\[Phi]}],
		Table[rIn*{Cos[fi],Sin[fi]}+{x,y},{fi,\[Phi]1,\[Phi]2,(\[Phi]2-\[Phi]1)/n\[Phi]}]
	};
	StructuredMesh[raster,{n\[Phi],nr}]
]


(* ::Subsubsection::Closed:: *)
(*CircularVoidMesh*)


CircularVoidMesh::usage="CircularVoidMesh[{x,y}, r, s, n] creates a square mesh of size s with circular void of radius r centered at {x,y}.";
CircularVoidMesh::ratio="Radius `1` should be smaller than the half of square domain size `2`.";

CircularVoidMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,_,_}};

CircularVoidMesh[{cx_,cy_},radius_,size_,n_Integer?Positive]:=Module[
	{raster,eighth,quarter},
	(* This should also make sure that numerical quantities are compared. *)
	If[
		Not@TrueQ[radius<(size/2)],
		Message[CircularVoidMesh::ratio,radius,size];Return[$Failed]
	];
		
	raster=N@{
		Table[{size/2,y}+{cx,cy},{y,-size/2,size/2,size/n}],
		Table[radius*{Cos[fi],Sin[fi]}+{cx,cy},{fi,-Pi/4,Pi/4,(Pi/2)/n}]
	};
	quarter=StructuredMesh[raster,{n,Ceiling[(size/radius/8)*n]}];
	
	MergeMesh[{
		quarter,
		TransformMesh[quarter,RotationTransform[Pi/2,{cx,cy}]],
		TransformMesh[quarter,RotationTransform[Pi,{cx,cy}]],
		TransformMesh[quarter,RotationTransform[3*Pi/2,{cx,cy}]]
	}]
]


(* ::Subsection::Closed:: *)
(*Named meshes 3D*)


(* ::Subsubsection::Closed:: *)
(*CuboidMesh*)


CuboidMesh::usage="CuboidMesh[{x1, y1, z1}, {x2, y2, z2}, {nx, ny, nz}] creates structured mesh of hexahedra on Cuboid.";

CuboidMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,_}};

CuboidMesh[n_Integer]:=CuboidMesh[{0,0,0},{1,1,1},{n,n,n}]

CuboidMesh[{x1_,y1_,z1_},{x2_,y2_,z2_},{nx_,ny_,nz_}]:=StructuredMesh[{
	{{{x1,y1,z1},{x2,y1,z1}},{{x1,y2,z1},{x2,y2,z1}}},
	{{{x1,y1,z2},{x2,y1,z2}},{{x1,y2,z2},{x2,y2,z2}}}
	},
	{nx,ny,nz}
];


(* ::Subsubsection::Closed:: *)
(*HexahedronMesh*)


HexahedronMesh::usage="HexahedronMesh[{p1, p2, ..., p8}, {nx, ny, nz}] creates structured mesh on Hexahedron.";
HexahedronMesh::ordering="Warning! Ordering of corners may be incorrect.";

HexahedronMesh//SyntaxInformation={"ArgumentsPattern"->{_,_.}};

HexahedronMesh[{nx_Integer,ny_Integer,nz_Integer}]:=HexahedronMesh[{{0,0,0},{1,0,0},{1,1,0},{0,1,0},{0,0,1},{1,0,1},{1,1,1},{0,1,1}},{nx,ny,nz}]

HexahedronMesh[{p1_,p2_,p3_,p4_,p5_,p6_,p7_,p8_},{nx_Integer,ny_Integer,nz_Integer}]:=Module[
	{mesh},
	Check[
		mesh=StructuredMesh[
			{{{p1,p2},{p4,p3}},{{p5,p6},{p8,p7}}},
			{nx,ny,nz}
		],
		Message[HexahedronMesh::ordering];mesh
	]
]


(* ::Subsubsection::Closed:: *)
(*CylinderMesh*)


CylinderMesh::usage="CylinderMesh[{{x1, y1, z1}, {x2, y2, z2}}, r, {nr,nz}] creates structured mesh on Cylinder.";
CylinderMesh::noelems="Specificaton of elements `1` must be an integer equal or larger than 2.";

CylinderMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,_,OptionsPattern[]}};

CylinderMesh[{nr_Integer,nz_Integer},opts:OptionsPattern[]]:=CylinderMesh[{{0,0,-1},{0,0,1}},1,{nr,nz},opts]

CylinderMesh[{{x1_,y1_,z1_},{x2_,y2_,z2_}},r_,{nr_Integer,nz_Integer},opts:OptionsPattern[]]:=Module[
	{order,diskMesh,length,alignedCylinder,tf},
	If[
		TrueQ[nr<2]||Not@IntegerQ[nr],
		Message[CylinderMesh::noelems,nr];Return[$Failed]
	];

	length=Norm[{x2,y2,z2}-{x1,y1,z1}];
	diskMesh=DiskMesh[{0,0},r,nr,FilterRules[{opts},Options@DiskMesh]];
	alignedCylinder=ExtrudeMesh[diskMesh,length,nz];
	tf=Last@FindGeometricTransform[{{x1,y1,z1},{x2,y2,z2}},{{0,0,0},{0,0,length}}];
	
	ToElementMesh[
		"Coordinates" -> (tf@alignedCylinder["Coordinates"]),
		"MeshElements" -> alignedCylinder["MeshElements"]
	]
]


(* ::Subsubsection::Closed:: *)
(*SphereMesh*)


(* 
Some key ideas for this code come from the answer by "Michael E2" on topic: 
https://mathematica.stackexchange.com/questions/85592/how-to-create-an-elementmesh-of-a-sphere
*)
SphereMesh::usage="SphereMesh[{x, y, z}, r, n] creates structured mesh with n elements on Sphere of radius r centered at {x,y,z}.";
SphereMesh::noelems="Specificaton of elements `1` must be an integer equal or larger than 2.";

SphereMesh//Options={"MeshOrder"->Automatic};

SphereMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,_,OptionsPattern[]}};

SphereMesh[n_Integer,opts:OptionsPattern[]]:=SphereMesh[{0,0,0},1,n,opts]

SphereMesh[{x_,y_,z_},r_,n_Integer,opts:OptionsPattern[]]:=Module[
	{order,rescale,cuboid,cuboidShell,coordinates},
	If[TrueQ[n<2]||Not@IntegerQ[n],Message[SphereMesh::noelems,n];Return[$Failed]];
	order=OptionValue["MeshOrder"]/.Automatic->1;
	If[Not@MatchQ[order,1|2],Message[ToElementMesh::femmonv,order,1];Return[$Failed]];
	
	rescale=(Max[Abs@#]*Normalize[#])&;
	(* This special raster makes all element edges on sphere edge of the same length. *)
	cuboid=With[
		{pts=r*N@Tan@Subdivide[-Pi/4,Pi/4,n]},
		StructuredMesh[Outer[Reverse@*List,pts,pts,pts],{n,n,n}]
	];
	(* If we do order alteration (more than 1st order) before projection, then geometry is
	more accurate and elements have curved edges. *)
	cuboidShell=MeshOrderAlteration[
		ToBoundaryMesh[cuboid],
		order
	];
	
	coordinates=Transpose[Transpose[rescale/@cuboidShell["Coordinates"]]+{x,y,z}];
	
	ToBoundaryMesh[
		"Coordinates" -> coordinates,
		"BoundaryElements" -> cuboidShell["BoundaryElements"]
	]
]


(* ::Subsubsection::Closed:: *)
(*SphericalShellMesh*)


SphericalShellMesh::usage="SphericalShellMesh[{x, y, z}, {rIn, rOut}, {n\[Phi], nr}] creates structured mesh on SphericalShell, with n\[Phi] elements in circumferential and nr elements in radial direction.";

SphericalShellMesh//Options={"MeshOrder"->Automatic};

SphericalShellMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,_,OptionsPattern[]}};

SphericalShellMesh[{n\[Phi]_Integer,nr_Integer},opts:OptionsPattern[]]:=SphericalShellMesh[{0,0,0},{1/2,1},{n\[Phi],nr},opts]

SphericalShellMesh[{x_,y_,z_},{rIn_,rOut_},{n\[Phi]_Integer,nr_Integer},opts:OptionsPattern[]]:=Module[
	{order,rescale,innerRaster,outerRaster,rotations,flatMesh,curvedMesh},
	
	order=OptionValue["MeshOrder"]/.Automatic->1;
	If[
		Not@MatchQ[order,1|2],
		Message[ToElementMesh::femmonv,order,1];Return[$Failed]
	];
	
	rescale=(Max[Abs@#]*Normalize[#])&;
	
	(* This special raster makes all element edges on disk edge of the same length. *)
	innerRaster=With[
		{pts=rIn*N@Tan@Subdivide[-Pi/4,Pi/4,n\[Phi]]},
		Map[Append[rIn], Outer[Reverse@*List,pts,pts], {2}]
	];
	outerRaster=With[
		{pts=rOut*N@Tan@Subdivide[-Pi/4,Pi/4,n\[Phi]]},
		Map[Append[rOut], Outer[Reverse@*List,pts,pts], {2}]
	];
	
	flatMesh=MeshOrderAlteration[
		StructuredMesh[{innerRaster,outerRaster},{n\[Phi],n\[Phi],nr}],
		order
	];
	curvedMesh=ToElementMesh[
		"Coordinates" ->Transpose[Transpose[rescale/@flatMesh["Coordinates"]]+{x,y,z}],
		"MeshElements" -> flatMesh["MeshElements"]
	];
	
	rotations=Join[
		RotationTransform[#,{1,0,0},{x,y,z}]&/@(Range[4]*Pi/2),
		RotationTransform[#,{0,1,0},{x,y,z}]&/@{Pi/2,3Pi/2}
	];
		
	MergeMesh@(TransformMesh[curvedMesh,#]&/@rotations)
]


(* ::Subsubsection::Closed:: *)
(*BallMesh*)


ballMeshBlock//ClearAll

ballMeshBlock[{x_,y_,z_},r_,n_Integer/;(n>=1)]:=Module[
	{rescale,bottomRaster,topRaster,cubeMesh,sideMesh,d,rotations,unitBall},
	
	(* Size of internal square. Optimial minimal element quality is obtained at 0.2.
	Value of 0.3 creates nicer element size distribution. *)
	d=0.3;
	rescale=(Max[Abs@#]*Normalize[#])&;
	
	bottomRaster=With[
		{pts=d*N@Subdivide[-1,1,n]},
		Map[Append[d], Outer[Reverse@*List,pts,pts], {2}]
	];
	
	(* This special raster makes all element edges on disk edge of the same length. *)
	topRaster=With[
		{pts=N@Tan@Subdivide[-Pi/4,Pi/4,n]},
		Map[rescale@*Append[1.], Outer[Reverse@*List,pts,pts], {2}]
	];
	
	cubeMesh=CuboidMesh[-d*{1,1,1},d*{1,1,1},{n,n,n}];
	(* TODO: Figure out how many elements should be in radial direction. *)
	sideMesh=StructuredMesh[{bottomRaster,topRaster},{n,n,n}];
	
	rotations=Join[
		RotationTransform[#,{0,1,0}]&/@({0,1,2,3}*Pi/2),
		RotationTransform[#,{1,0,0}]&/@({1,3}*Pi/2)
	];
	
	unitBall=MergeMesh@Join[{cubeMesh},TransformMesh[sideMesh,#]&/@rotations];
	
	ToElementMesh[
		"Coordinates" ->Transpose[Transpose[r*unitBall["Coordinates"]]+{x,y,z}],
		"MeshElements" -> unitBall["MeshElements"]
	]
]


(* 
Some key ideas for this code come from the answer by "Michael E2" on topic: 
https://mathematica.stackexchange.com/questions/85592/how-to-create-an-elementmesh-of-a-sphere
*)
ballMeshProjection//ClearAll

ballMeshProjection[{x_,y_,z_},r_,n_Integer/;(n>=1)]:=Module[
	{rescale,cuboidMesh,coordinates},
	
	rescale=(Max[Abs@#]*Normalize[#])&;
	(* This special raster makes all element edges on sphere edge of the same length. *)
	cuboidMesh=With[
		{pts=N@Tan@Subdivide[-Pi/4,Pi/4,n]},
		StructuredMesh[Outer[Reverse@*List,pts,pts,pts],{n,n,n}]
	];
	(* If we do order alteration (more than 1st order) before projection, then geometry is
	more accurate and elements have curved edges. *)
	(*cuboidMesh=MeshOrderAlteration[cuboidMesh,order];*)
	
	coordinates=Transpose[Transpose[r*(rescale/@cuboidMesh["Coordinates"])]+{x,y,z}];
	
	ToElementMesh[
		"Coordinates" -> coordinates,
		"MeshElements" -> cuboidMesh["MeshElements"]
	]
]


BallMesh::usage="BallMesh[{x, y, z}, r, n] creates structured mesh with n elements on Ball of radius r centered at {x,y,z}.";
BallMesh::noelems="Specificaton of elements `1` must be an integer equal or larger than 1.";
BallMesh::method="Method \"`1`\" is not supported.";

BallMesh//Options={Method->Automatic};

BallMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,_,OptionsPattern[]}};

BallMesh[n_Integer,opts:OptionsPattern[]]:=BallMesh[{0,0,0},1,n,opts]

BallMesh[{x_,y_,z_},r_,n_Integer,opts:OptionsPattern[]]:=Module[
	{order,method},
	
	If[
		Not@(TrueQ[n>=1]&&IntegerQ[n]),
		Message[BallMesh::noelems,n];Return[$Failed]
	];
	
	method=OptionValue[Method]/.Automatic->"Block";
	
	Switch[method,
		"Block",ballMeshBlock[{x,y,z},r,n],
		"Projection",ballMeshProjection[{x,y,z},r,n],
		_,Message[BallMesh::method,method];$Failed
	]
]


(* ::Subsubsection::Closed:: *)
(*SphericalVoidMesh*)


SphericalVoidMesh::usage="SphericalVoidMesh[voidRadius, cuboidSize, noElements] creates a mesh with spherical void in cuboid domain.";

SphericalVoidMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,_,OptionsPattern[]}};

SphericalVoidMesh[voidRadius_,cuboidSize_,noElements_Integer,opts:OptionsPattern[]]:=Module[
	{r,s,n,rescale,outerRaster,innerRaster,basicMesh,rt},
	
	rescale=(Max[Abs@#]*Normalize[#])&;
	
	s=cuboidSize;
	r=Clip[voidRadius,{0.01,Infinity}];
	n=noElements;
	
	outerRaster=With[
		{pts=s*N@Subdivide[0,1,n]},
		Map[Append[s], Outer[Reverse@*List,pts,pts], {2}]
	];
	(* This special raster makes all element edges on sphere edge of the same length. *)
	innerRaster=With[
		{pts=r*N@Tan@Subdivide[0,Pi/4,n]},
		Map[rescale@*Append[r], Outer[Reverse@*List,pts,pts], {2}]
	];
	(* In "thickness" direction the number of elements is estimated so that their
	edges have similar length. *)
	basicMesh=StructuredMesh[{innerRaster,outerRaster},{n,n,Ceiling[n*(s/r/2)]}];

	rt=RotationTransform[#*(2Pi/3),{1,1,1},{0,0,0}]&/@{0,1,2};
	MergeMesh[TransformMesh[basicMesh,#]&/@rt]
]


(* ::Subsubsection::Closed:: *)
(*EllipsoidVoidMesh*)


(* ::Text:: *)
(*This is a quick prototype, made for analysis of voids inside material (forging).*)


(* 
Projection (with RegionNearest) of points from one side of the cube to a sphere. 
Argument f should be a Function to specify on which side of cube points are created (e.g. {1,#1,#2}& ). 
It is assumed size of domain is 1.
*)
voidRaster//ClearAll

voidRaster[f_Function,semiAxis:{_,_,_}]:=Module[
	{n=30,pts,sidePts,innerPts,middlePts},
	pts=N@Subdivide[0,1,n-1];
	sidePts=Flatten[Outer[f,pts,pts],1];
	innerPts=RegionNearest[Ellipsoid[{0,0,0},semiAxis],sidePts];
	middlePts=RegionNearest[Ellipsoid[{0,0,0},semiAxis*2],sidePts];
	{Partition[sidePts,n],Partition[middlePts,n],Partition[innerPts,n]}
]


EllipsoidVoidMesh::usage=
	"EllipsoidVoidMesh[radius, noElements] creates a mesh with spherical void."<>"\n"<>
	"EllipsoidVoidMesh[{r1, r2, r3}, noElements] creates a mesh with ellipsoid void with semi-axis radii r1, r2 and r3.";

EllipsoidVoidMesh//SyntaxInformation={"ArgumentsPattern"->{_,_}};

EllipsoidVoidMesh[{r1_,r2_,r3_},noElements_Integer]:=With[{
	dim=Clip[#,{0.01,0.8}]&/@{r1,r2,r3},
	n=Round@Clip[noElements,{1,100}]
	},
	Fold[
		MergeMesh[#1,#2]&,
		{
		StructuredMesh[voidRaster[{1,#1,#2}&,dim],n{1,1,2}],
		StructuredMesh[voidRaster[{#2,1,#1}&,dim],n{1,1,2}],
		StructuredMesh[voidRaster[{#1,#2,1}&,dim],n{1,1,2}]
		}
	]
]

(* Implementation for spherical void is faster, because (costly) StructuredMesh is generated
only once and then rotated. *)
EllipsoidVoidMesh[voidRadius_,noElements_Integer]:=Module[{
	dim=Clip[voidRadius,{0.01,0.8}]*{1,1,1},
	n=Round@Clip[noElements,{1,100}],
	rotations=RotationTransform[#,{1,1,1},{0,0,0}]&/@{0,2Pi/3,4Pi/3},
	basicMesh
	},
	basicMesh=StructuredMesh[voidRaster[{1,#1,#2}&,dim],n{1,1,2}];
	Fold[
		MergeMesh[#1,#2]&,
		TransformMesh[basicMesh,#]&/@rotations
	]
]


(* ::Subsubsection::Closed:: *)
(*TetrahedronMesh*)


splitTetrahedronToHexahedra[{p1_,p2_,p3_,p4_},n_Integer]:=Module[
	{n1,n2,n3,n4,x,connectivity},
	(* Make ordering of nodes consistent with TetrahedronElement *)
	{n1,n2,n3,n4}=reorientSimplex[{p1,p2,p3,p4}];
	
	x=Join[{n1,n2,n3,n4},Mean/@{
		{n1,n2},{n2,n3},{n3,n1},{n2,n4},{n3,n4},{n1,n4},
		{n4,n3,n2},{n4,n1,n3},{n4,n2,n1},{n1,n2,n3},
		{n1,n2,n3,n4}
		}
	];
	
	connectivity={
		{
			{{x[[1]],x[[5]]},{x[[7]],x[[14]]}},
			{{x[[10]],x[[13]]},{x[[12]],x[[15]]}}
		},
		{
			{{x[[5]],x[[2]]},{x[[14]],x[[6]]}},
			{{x[[13]],x[[8]]},{x[[15]],x[[11]]}}
		},
		{
			{{x[[7]],x[[14]]},{x[[3]],x[[6]]}},
			{{x[[12]],x[[15]]},{x[[9]],x[[11]]}}
		},
		{
			{{x[[10]],x[[13]]},{x[[12]],x[[15]]}},
			{{x[[4]],x[[8]]},{x[[9]],x[[11]]}}
		}
	};
	MergeMesh@Map[
		StructuredMesh[#,{n,n,n}]&,
		connectivity
	]
]


TetrahedronMesh::usage="TetrahedronMesh[{p1,p2,p3,p4}, n] creates tetrahedral mesh on Tetrahedron with corners p1, p2, p3 and p4.";
TetrahedronMesh::tetelms="Only 2, 4, 8 or 16 elements per edge is allowed for tetrahedral mesh.";
TetrahedronMesh::hexelms="Only even number of elements per edge is allowed for hexahedral mesh.";
TetrahedronMesh::badtype="Unknown value `1` for option \"MeshElementType\".";

TetrahedronMesh//Options={"MeshElementType"->HexahedronElement};

TetrahedronMesh//SyntaxInformation={"ArgumentsPattern"->{_,_,OptionsPattern[]}};

TetrahedronMesh[n_Integer,opts:OptionsPattern[]]:=TetrahedronMesh[{{0,0,0},{1,0,0},{0,1,0},{0,0,1}},n,opts]

TetrahedronMesh[{p1_,p2_,p3_,p4_},n_Integer,opts:OptionsPattern[]]:=Module[
	{type},
	
	type=OptionValue["MeshElementType"];
	If[
		(type===TetrahedronElement)&&Not@MemberQ[{2,4,8,16},n],
		Message[TetrahedronMesh::tetelms];Return[$Failed]
	];
	
	If[
		(type===HexahedronElement)&&OddQ[n],
		Message[TetrahedronMesh::hexelms];Return[$Failed]
	];
	
	Switch[type,
		TetrahedronElement,simplexMesh[Tetrahedron,{p1,p2,p3,p4},n],
		HexahedronElement,splitTetrahedronToHexahedra[{p1,p2,p3,p4},n/2],
		_,Message[TetrahedronMesh::badtype,type];$Failed
	]
]


(* ::Subsubsection::Closed:: *)
(*PrismMesh*)


(* Helper function to determine if points given as Prism corners need reordering. *)
reorientPrismQ[pts_]:=With[{
	a=pts[[2]]-pts[[1]],
	b=pts[[3]]-pts[[1]],
	c=pts[[4]]-pts[[1]]
	},
	Negative[Cross[a,b].c]
]


PrismMesh::usage="PrismMesh[{p1, ..., p6},{n1, n2}] creates structured mesh on Prism, with n1 and n2 elements per edge.";
PrismMesh::noelems="Specificaton of elements `1` must be even integer equal or larger than 2.";
PrismMesh::alignerr="Warning! Corner alignment error `1` is larger than tolerance.";

PrismMesh//SyntaxInformation={"ArgumentsPattern"->{_,_}};

PrismMesh[{n1_Integer,n2_Integer}]:=PrismMesh[{{0,0,0},{1,0,0},{0,1,0},{0,0,1},{1,0,1},{0,1,1}},{n1,n2}]

PrismMesh[corners_List,{n1_Integer,n2_Integer}]:=Module[
	{pts,error,triangleMesh,standardPrism,tf},
	If[
		Not@(TrueQ[n1>=2]&&EvenQ[n1]),
		Message[PrismMesh::noelems,n1];Return[$Failed]
	];
	
	pts=If[
		reorientPrismQ[corners],
		Join@@Reverse@TakeDrop[corners,3],
		corners
	];
	(* Smoothing TriangleMesh before extrusion seems to even worsen the quality of hex mesh. *)
	triangleMesh=TriangleMesh[{{0,0},{1,0},{0,1}},n1,"MeshElementType"->QuadElement];
	standardPrism=ExtrudeMesh[triangleMesh,1,n2];
	(* Find TransformationFunction between standard and arbitrary prism. "Linear" method
	is much faster than others. *)
	{error,tf}=FindGeometricTransform[
		pts,
		{{0,0,0},{1,0,0},{0,1,0},{0,0,1},{1,0,1},{0,1,1}},
		Method->"Linear"
	];
	(* Alignment error is non-zero in case of non-homogenous transformation. 
	Currently the tolerance is chosen arbitrarily. *)
	If[error>10^-4,Message[PrismMesh::alignerr,ScientificForm[error,4]]];
		
	ToElementMesh[
		"Coordinates" ->(tf@standardPrism["Coordinates"]),
		"MeshElements" -> standardPrism["MeshElements"]
	]
]


(* ::Section::Closed:: *)
(*End package*)


End[]; (* "`Private`" *)


EndPackage[];
