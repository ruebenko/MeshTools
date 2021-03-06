#!/usr/bin/env wolframscript
(* ::Package:: *)

(* ::Text:: *)
(*This script builds the MeshTools-X.Y.Z.paclet. The creation is two step process. First the source code and other files need to be copied alongside the documentation and then the paclet file is created. Previously documentation should be generated separately with Workbench as outlined in the README.md file.*)


(* ::Subsubsection:: *)
(*Git functions*)


getGitRevision[dir_]:=Module[{description},
	SetDirectory[dir];
	(* For meaning of this see: https://git-scm.com/docs/git-describe *)
	description=First[
		ReadList["!git describe --long --tags --dirty --always",String],
		Return[$Failed]
	];
	ResetDirectory[];
	description
]


getGitCommitCount[dir_]:=Module[{value},
	SetDirectory[dir];
	(* For meaning of this see: https://git-scm.com/docs/git-describe *)
	value=First[
		ReadList["!git rev-list --count HEAD",Number],
		Return[$Failed]
	];
	ResetDirectory[];
	value
]


(* ::Subsubsection:: *)
(*Build procedure*)


$name="MeshTools";
(* Get the distribution directory by using this notebook\[CloseCurlyQuote]s directory. *)
$source=If[$Notebooks,NotebookDirectory[],Directory[]];
(* Construct the target directory from this notebooks base directory. *)
$target=FileNameJoin[{$source,"build",$name}];


$helpMessage=("  Script to build the paclet and install it.
  Usage: Build.wls [options]

  Options:
    -h, --help                   Output usage information
    --release                    Build public release")


Module[{directories},
	If[
		MemberQ[Rest@$ScriptCommandLine,"/?"|"-h"|"--help"],
		Print[$helpMessage];Quit[1]
	];
	
	If[
		Not@DirectoryQ[$target],
		CreateDirectory[$target,CreateIntermediateDirectories->True]
	];
	(* Copy neccesseary files from the source to the target directory. *)
	Map[
		CopyFile[
			FileNameJoin[{$source,#}],
			FileNameJoin[{$target,#}],
			OverwriteTarget->True
		]&,
		{"MeshTools.wl","PacletInfo.m"}
	];
	(* Delete old and copy the new source directories. 
	"Documentation" directory is already created by documentation build procedure. *)
	directories={"FrontEnd","Kernel"};
	Map[
		If[
			FileExistsQ[FileNameJoin[{$target,#}]],
			DeleteDirectory[FileNameJoin[{$target,#}],DeleteContents->True]
		]&,
		directories
	];
	Map[
		CopyDirectory[FileNameJoin[{$source,#}],FileNameJoin[{$target,#}]]&,
		directories
	];
]


Module[{original, modified,noCommits,revision,internalQ},

	original=Import[FileNameJoin[{$source,"PacletInfo.m"}]];
	noCommits=getGitCommitCount[$source];
	revision=getGitRevision[$source];
	internalQ=Not@MemberQ[Rest@$ScriptCommandLine,"--release"];
		
	(* Description of git repository (git describe ...) returns a string that cannot 
	be used as BuildNumber because only integers are accepted. 
	Otherwise PackPaclet returns $Failed and procedure fails. Instead now commit count is used. *)
	modified=Fold[
			Insert[#1,#2,4]&,
			original,
			{Internal->internalQ,BuildNumber->noCommits,"Hash"->revision}
	];
	
	Export[
		FileNameJoin[{$target,"PacletInfo.m"}],
		modified,
		"Comments"->{"Paclet Info File","Created on "<>DateString[]}
	];
]


Module[{pacletPath,newPaclet},
	Needs["PacletManager`"];
	
	(* Change into the build directory and create the paclet. *)	
	SetDirectory[FileNameJoin[{$source,"build"}]];
	pacletPath=PackPaclet[$name];
	ResetDirectory[];
	
	(*Uninstall all previous versions. *)
	If[PacletFind[$name]=!={},PacletUninstall[$name]];
	newPaclet=PacletInstall[pacletPath];
	RebuildPacletData[];
	
	If[
		Length@PacletFind["MeshTools"]===1,
		Print["Paclet build succesfull."];Quit[0],
		Print["Paclet build failed."];Quit[1]
	]
]
