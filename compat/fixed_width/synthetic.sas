/*-------------------------------------------------------------------------
 |                             SAS SETUP FILE
 |           A SYNTHETIC SURVEY IN THE STYLE OF CDC'S NSFG SETUPS
 | Sections: LIBNAME, PROC FORMAT, DATA, INFILE, INPUT, LABEL,
 | MISSING VALUE RECODES ("user-defined" codes to SAS's .), FORMAT.
 |------------------------------------------------------------------------*/

* DEFINING THE PATH TO PERMANENT SAS DATA SET LOCATION;

libname "data-file-path";

* SAS PROC FORMAT;

PROC FORMAT;
  VALUE q01f  1='(1) Yes' 2='(2) No' 8='(8) DK' 9='(9) Not ascertained' ;
  VALUE q02f  1='(1) Yes' 2='(2) No' 8='(8) DK' 9='(9) Not ascertained' ;
  VALUE q03f  1='(1) Yes' 2='(2) No' 8='(8) DK' 9='(9) Not ascertained' ;
  VALUE q04f  1='(1) Yes' 2='(2) No' 8='(8) DK' 9='(9) Not ascertained' ;
  VALUE q05f  1='(1) Yes' 2='(2) No' 8='(8) DK' 9='(9) Not ascertained' ;
  VALUE q06f  1='(1) Yes' 2='(2) No' 8='(8) DK' 9='(9) Not ascertained' ;
  VALUE q07f  1='(1) Yes' 2='(2) No' 8='(8) DK' 9='(9) Not ascertained' ;
  VALUE q08f  1='(1) Yes' 2='(2) No' 8='(8) DK' 9='(9) Not ascertained' ;
  VALUE q09f  1='(1) Yes' 2='(2) No' 8='(8) DK' 9='(9) Not ascertained' ;
  VALUE q10f  1='(1) Yes' 2='(2) No' 8='(8) DK' 9='(9) Not ascertained' ;
  VALUE q11f  1='(1) Yes' 2='(2) No' 8='(8) DK' 9='(9) Not ascertained' ;
  VALUE q12f  1='(1) Yes' 2='(2) No' 8='(8) DK' 9='(9) Not ascertained' ;
  VALUE age1f  98='(98) DK' 99='(99) Not ascertained' ;
  VALUE age2f  98='(98) DK' 99='(99) Not ascertained' ;
  VALUE age3f  98='(98) DK' 99='(99) Not ascertained' ;
  VALUE age4f  98='(98) DK' 99='(99) Not ascertained' ;
  VALUE age5f  98='(98) DK' 99='(99) Not ascertained' ;
  VALUE age6f  98='(98) DK' 99='(99) Not ascertained' ;
  VALUE incomef  0='(0) None' 999998='(999998) Refused' ;
  VALUE childrenf  0='(0) None' 97='(97) Refused' 98='(98) DK' 99='(99) Not ascertained' ;
  VALUE statef  -1='(-1) Abroad' 6='(6) California' 36='(36) New York' ;
  VALUE religionf  1='(1) None' 2='(2) Catholic' 3='(3) Protestant' ;
  VALUE flag1f  0='(0) No imputation' 1='(1) Hot deck imputation' ;
  VALUE flag2f  0='(0) No imputation' 1='(1) Hot deck imputation' ;

* SAS DATA, INFILE, INPUT STATEMENTS;

DATA ;
INFILE "c:\temp\synthetic.dat" LRECL=62;
INPUT
        CASEID 1-5              Q01 6                   Q02 7                   
        Q03 8                   Q04 9                   Q05 10                  
        Q06 11                  Q07 12                  Q08 13                  
        Q09 14                  Q10 15                  Q11 16                  
        Q12 17                  AGE1 18-19              AGE2 20-21              
        AGE3 22-23              AGE4 24-25              AGE5 26-27              
        AGE6 28-29              INCOME 30-35            WEIGHT 36-44            
        CHILDREN 45-46          CMBIRTH 47-50           STATE 51-52             
        RELIGION 53-54          INTVWR $ 55-57          FLAG1 58                
        FLAG2 59                BLANK 60-62             AGE1_TENS 18            
        CASE_LAST2 4-5          
        ;


* SAS LABEL STATEMENT;

LABEL
   CASEID  = 'Case identification number'
   Q01     = 'Question 1: did R''s family agree; "yes" or no'
   Q02     = 'Question 2: did R''s family agree; "yes" or no'
   Q03     = 'Question 3: did R''s family agree; "yes" or no'
   Q04     = 'Question 4: did R''s family agree; "yes" or no'
   Q05     = 'Question 5: did R''s family agree; "yes" or no'
   Q06     = 'Question 6: did R''s family agree; "yes" or no'
   Q07     = 'Question 7: did R''s family agree; "yes" or no'
   Q08     = 'Question 8: did R''s family agree; "yes" or no'
   Q09     = 'Question 9: did R''s family agree; "yes" or no'
   Q10     = 'Question 10: did R''s family agree; "yes" or no'
   Q11     = 'Question 11: did R''s family agree; "yes" or no'
   Q12     = 'Question 12: did R''s family agree; "yes" or no'
   AGE1    = 'Age at event 1'
   AGE2    = 'Age at event 2'
   AGE3    = 'Age at event 3'
   AGE4    = 'Age at event 4'
   AGE5    = 'Age at event 5'
   AGE6    = 'Age at event 6'
   INCOME  = 'Family income in dollars'
   WEIGHT  = 'Post-stratified weight'
   CHILDREN= 'Number of children ever born'
   CMBIRTH = 'Century month of birth (blank when not asked)'
   STATE   = 'State of residence'
   RELIGION= 'Religion raised in'
   INTVWR  = 'Interviewer initials'
   FLAG1   = 'Imputation flag'
   FLAG2   = 'Imputation flag'
   BLANK   = 'Blank'
   AGE1_TENS = 'Tens digit of age at event 1'
   CASE_LAST2 = 'Last two digits of case'
        ;


* USER-DEFINED MISSING VALUES RECODE TO SAS SYSMIS;

   IF (Q01 = 8 OR Q01 = 9) THEN Q01 = .;
   IF (Q02 = 8 OR Q02 = 9) THEN Q02 = .;
   IF (Q04 = 8 OR Q04 = 9) THEN Q04 = .;
   IF (Q05 = 8 OR Q05 = 9) THEN Q05 = .;
   IF (Q06 = 9) THEN Q06 = .;
   IF (Q07 = 8 OR Q07 = 9) THEN Q07 = .;
   IF (Q08 = 8 OR Q08 = 9) THEN Q08 = .;
   IF (Q10 = 8 OR Q10 = 9) THEN Q10 = .;
   IF (Q11 = 8 OR Q11 = 9) THEN Q11 = .;
   IF (Q12 = 9) THEN Q12 = .;
   IF (AGE1 = 98 OR AGE1 = 99) THEN AGE1 = .;
   IF (AGE2 = 98 OR AGE2 = 99) THEN AGE2 = .;
   IF (AGE3 = 98 OR AGE3 = 99) THEN AGE3 = .;
   IF (AGE4 = 98 OR AGE4 = 99) THEN AGE4 = .;
   IF (AGE5 = 98 OR AGE5 = 99) THEN AGE5 = .;
   IF (AGE6 = 98 OR AGE6 = 99) THEN AGE6 = .;
   IF (INCOME = 999998) THEN INCOME = .;
   IF (CHILDREN = 97 OR CHILDREN = 98 OR CHILDREN = 99) THEN CHILDREN = .;
   IF (RELIGION = 99) THEN RELIGION = .;


* SAS FORMAT STATEMENT;

  FORMAT
         Q01 q01f.
         Q02 q02f.
         Q03 q03f.
         Q04 q04f.
         Q05 q05f.
         Q06 q06f.
         Q07 q07f.
         Q08 q08f.
         Q09 q09f.
         Q10 q10f.
         Q11 q11f.
         Q12 q12f.
         AGE1 age1f.
         AGE2 age2f.
         AGE3 age3f.
         AGE4 age4f.
         AGE5 age5f.
         AGE6 age6f.
         INCOME incomef.
         CHILDREN childrenf.
         STATE statef.
         RELIGION religionf.
         FLAG1 flag1f.
         FLAG2 flag2f.
  ;

RUN ;
