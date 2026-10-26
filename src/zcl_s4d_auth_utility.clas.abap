CLASS zcl_s4d_auth_utility DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    TYPES t_role_name TYPE if_iam_business_role=>ty_id.
    TYPES t_template  TYPE if_iam_business_role=>ty_brt_id.
    TYPES tt_users TYPE STANDARD TABLE OF syuname
                    WITH EMPTY KEY.
    TYPES t_catalog_id TYPE if_iam_business_role=>ty_bu_catalog_id.
    TYPES tt_catalogs TYPE STANDARD TABLE OF t_catalog_id
                       WITH EMPTY KEY.
    TYPES tt_log TYPE string_table.


    DATA log TYPE string_table READ-ONLY.

    CLASS-METHODS class_constructor.

    CLASS-METHODS
      create_and_assign_role
        IMPORTING
          i_role_name TYPE t_role_name
          i_template  TYPE t_template
          i_users     TYPE tt_users
          i_catalogs  TYPE tt_catalogs OPTIONAL
          i_space     TYPE if_iam_business_role=>ty_flp_space_id OPTIONAL
        CHANGING
          c_log       TYPE tt_log.

    CLASS-METHODS
      create_and_assign_brole
        IMPORTING
          i_template  TYPE t_template
          i_role_name TYPE t_role_name
          i_users     TYPE tt_users
        EXPORTING
          e_brole     TYPE REF TO if_iam_business_role
        CHANGING
          c_log       TYPE tt_log.

    CLASS-METHODS
      update_existing_role
        IMPORTING
          i_role_name TYPE t_role_name
          i_catalogs  TYPE tt_catalogs
        CHANGING
          c_log       TYPE tt_log.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA: br_factory TYPE REF TO if_iam_business_role_factory.

    CLASS-METHODS
      add_catalogs_to_role
        IMPORTING
                  i_brole    TYPE REF TO if_iam_business_role
                  i_catalogs TYPE tt_catalogs
        CHANGING  c_log      TYPE tt_log.

    CLASS-METHODS
      add_space_to_role
        IMPORTING
                  i_brole TYPE REF TO if_iam_business_role
                  i_space TYPE if_iam_business_role=>ty_flp_space_id
        CHANGING  c_log   TYPE tt_log.

ENDCLASS.



CLASS ZCL_S4D_AUTH_UTILITY IMPLEMENTATION.


  METHOD class_constructor.
    br_factory = cl_iam_business_role_factory=>create_instance( ).
  ENDMETHOD.


  METHOD create_and_assign_role.

* Get factory instance
    DATA(br_factory) = cl_iam_business_role_factory=>create_instance( ).

* Check if business role already exists
    br_factory->query_business_roles(
      EXPORTING
        ir_brole_id = VALUE #( ( sign = 'I'
                                 option = 'EQ'
                                 low = i_role_name )
                             )
      IMPORTING
        et_result   = DATA(result) ).

    IF result IS INITIAL.
* Create new business role from template
      br_factory->create_brole_from_template(
        EXPORTING
          iv_id            = i_role_name
          iv_template_id   = i_template
        IMPORTING
          eo_business_role = DATA(brole)
          et_return        = DATA(return) ).

      IF return IS NOT INITIAL.
        APPEND |Error creating role { i_role_name }.| TO c_log.
      ELSE.
        APPEND |Created business role { i_role_name }.| TO c_log.
        " Set Business Role: Read = unrestricted, Write = Unrestricted, F4 = unrestricted
        brole->set_access_restriction(
          EXPORTING
            iv_write  = if_iam_business_role=>co_access_restriction_code-unrestricted
            iv_read   = if_iam_business_role=>co_access_restriction_code-unrestricted
            iv_f4     = if_iam_business_role=>co_access_restriction_code-unrestricted
          IMPORTING
            et_return = return ).
      ENDIF.

    ELSE.

      APPEND |Business Role { i_role_name } already exists| TO c_log.

* Read existing business role
      br_factory->get_business_role(
       EXPORTING
              iv_uuid          = result[ 1 ]-uuid
        IMPORTING
              eo_business_role = brole
                    et_return  = return
                            ).
      IF return IS NOT INITIAL.
        APPEND |Error retrieving business role { i_role_name }| TO c_log.
      ENDIF.

    ENDIF.

* Assign users to business role
    IF brole IS BOUND.
      LOOP AT i_users INTO DATA(user).
        DATA(counter) = sy-tabix.
        brole->add_user(
          EXPORTING
            iv_user_id = user
          IMPORTING
            et_return  = return ).

        "ignore error that role is already assigned
        DELETE return WHERE id =  'APS_IAM_BUS_ROLE' AND number = '007'.

        IF return IS NOT INITIAL.
          APPEND |Error assigning role { i_role_name } to user {  user }.| TO c_log.
          EXIT.
        ENDIF.
*
      ENDLOOP.

      APPEND |Assigned role { i_role_name } to { counter } users.| TO c_log.

**********************************************************************
* Add the passed business catalogs to the business role.
**********************************************************************
      zcl_s4d_auth_utility=>add_catalogs_to_role(
      EXPORTING
        i_brole    = brole
        i_catalogs = i_catalogs
      CHANGING
        c_log      = c_log
    ).


**********************************************************************
* Add the passed Fiori launchpad space to the business role.
**********************************************************************
      zcl_s4d_auth_utility=>add_space_to_role(
        EXPORTING
          i_brole = brole
          i_space = i_space
        CHANGING
          c_log   = c_log
      ).


      brole->save(
        IMPORTING
          et_return = return ).
      IF return IS NOT INITIAL.
        APPEND |Error saving role { i_role_name }.| TO c_log.
      ELSE.
        APPEND |Saved role { i_role_name }.| TO c_log.
      ENDIF.
    ENDIF.

  ENDMETHOD.


  METHOD update_existing_role.

    " Get factory instance
    DATA(br_factory) = cl_iam_business_role_factory=>create_instance( ).

    " Read the business role
    br_factory->query_business_roles(
      EXPORTING
        ir_brole_id = VALUE #( ( sign   = 'I'
                                 option = 'EQ'
                                 low    = i_role_name ) )
      IMPORTING
        et_result   = DATA(result) ).

    IF result IS INITIAL.
      APPEND |Error: Business role { i_role_name } not found| TO c_log.
      RETURN.
    ENDIF.

    br_factory->get_business_role(
      EXPORTING
        iv_uuid          = result[ 1 ]-uuid
      IMPORTING
        eo_business_role = DATA(brole)
        et_return        = DATA(return)
    ).
    IF return IS NOT INITIAL.
      APPEND |Error retrieving business role { i_role_name }| TO c_log.
      RETURN.
    ENDIF.

***************************************************************************
* The following loop was replaced by calling method add_catalogs_to_role().
***************************************************************************
*    LOOP AT i_catalogs INTO DATA(catalog).
*
*      brole->add_business_catalog(
*        EXPORTING
*           iv_bu_catalog_id = catalog
*        IMPORTING
*           et_return        = return
*        ).
*
*      IF return IS NOT INITIAL.
*        APPEND return[ 1 ]-message TO c_log.
*      ELSE.
*        APPEND |Added catalog { catalog } to business role { i_role_name }| TO c_log.
*      ENDIF.
*
*    ENDLOOP.

**********************************************************************
* Add the passed business catalogs to the business role.
**********************************************************************
    zcl_s4d_auth_utility=>add_catalogs_to_role(
     EXPORTING
       i_brole    = brole
       i_catalogs = i_catalogs
     CHANGING
       c_log      = c_log
   ).


    brole->save(
      IMPORTING
        et_return = return ).
    IF return IS NOT INITIAL.
      APPEND |Error saving role { i_role_name }.| TO c_log.
    ELSE.
      APPEND |Saved role { i_role_name }.| TO c_log.
    ENDIF.

  ENDMETHOD.


  METHOD add_catalogs_to_role.
    LOOP AT i_catalogs INTO DATA(catalog).
      i_brole->add_business_catalog(
        EXPORTING
           iv_bu_catalog_id = catalog
        IMPORTING
           et_return        = DATA(return)
        ).
      IF return IS NOT INITIAL.
        APPEND return[ 1 ]-message TO c_log.
      ELSE.
        APPEND |Added catalog { catalog } to business role { i_brole->get_id( ) }| TO c_log.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_space_to_role.
    i_brole->add_flp_space(
      EXPORTING
        iv_flp_space_id = i_space
      IMPORTING
        et_return       = DATA(return)
    ).
    IF return IS NOT INITIAL.
      APPEND return[ 1 ]-message TO c_log.
    ELSE.
      APPEND |Added Fiori launchpad space { i_space } to business role { i_brole->get_id( ) }| TO c_log.
    ENDIF.
  ENDMETHOD.


  METHOD create_and_assign_brole.
*   Check if business role already exists
    br_factory->query_business_roles(
      EXPORTING
        ir_brole_id = VALUE #( ( sign = 'I'
                                 option = 'EQ'
                                 low = i_role_name ) )
      IMPORTING
        et_result   = DATA(result) ).

    IF result IS INITIAL.
*   Create new business role from template
      br_factory->create_brole_from_template(
        EXPORTING
          iv_id            = i_role_name
          iv_template_id   = i_template
        IMPORTING
          eo_business_role = DATA(brole)
          et_return        = DATA(return) ).

      IF return IS NOT INITIAL.
        APPEND |Error creating role { i_role_name }.| TO c_log.
      ELSE.
        APPEND |Created business role { i_role_name }.| TO c_log.

        " Set Business Role: Read = unrestricted, Write = Unrestricted, F4 = unrestricted
        brole->set_access_restriction(
          EXPORTING
            iv_write  = if_iam_business_role=>co_access_restriction_code-unrestricted
            iv_read   = if_iam_business_role=>co_access_restriction_code-unrestricted
            iv_f4     = if_iam_business_role=>co_access_restriction_code-unrestricted
          IMPORTING
            et_return = return ).
      ENDIF.

    ELSE.
      APPEND |Business Role { i_role_name } already exists| TO c_log.

*     Read existing business role
      br_factory->get_business_role(
       EXPORTING
              iv_uuid          = result[ 1 ]-uuid
        IMPORTING
              eo_business_role = brole
                    et_return  = return
                            ).

      IF return IS NOT INITIAL.
        APPEND |Error retrieving business role { i_role_name }| TO c_log.
      ENDIF.

    ENDIF.

*   Assign users to business role
    IF brole IS BOUND.
      e_brole = brole.
      DATA(counter) = 0.
      LOOP AT i_users INTO DATA(user).
        counter += 1.
        brole->add_user(
          EXPORTING
            iv_user_id = user
          IMPORTING
            et_return = return ).

        "ignore error that role is already assigned
        DELETE return WHERE id = 'APS_IAM_BUS_ROLE' AND number = '007'.

        IF return IS NOT INITIAL.
          APPEND |Error assigning role { i_role_name } to user { user }.| TO c_log.
          EXIT.
        ENDIF.
      ENDLOOP.

      APPEND |Assigned role { i_role_name } to { counter } users.| TO c_log.


*      brole->save(
*        IMPORTING
*          et_return = return ).
*      IF return IS NOT INITIAL.
*        APPEND |Error saving role { i_role_name }.| TO c_log.
*      ELSE.
*        APPEND |Saved role { i_role_name }.| TO c_log.
*      ENDIF.

    ENDIF.

  ENDMETHOD.
ENDCLASS.
