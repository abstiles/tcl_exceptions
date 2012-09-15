#!/usr/bin/tclsh

package provide exceptions 1.0

namespace eval exceptions {
namespace export try raise
################################################################################
# Example usage:
# try {
#     Code that may need cleanup
#     and/or
#     Code with potential errors
# } catch -ex ExceptionType {
#     ExceptionType handling code...
# } catch -gl {Index*Error} {
#     Code to handle e.g., IndexOutOfRangeError, IndexTypeError...
# } catch -re {Bad(Arg|Data)Error} {
#     Code to handle BadArgError or BadDataError...
# } catch * {
#     Code to catch anything not handled by the previous catch blocks...
# } finally {
#     Cleanup code that always executes
# }
################################################################################
proc try {args} {
	if {[catch consume_arg try_block]} {
		raise ArgumentError "Wrong number of args: should be try code_block\
			?catch type code_block?* ?finally code_block?"
	}

	set catch_list {}
	set finally_block {}

	while {[llength $args]} {
		# Process the arguments to try
		set try_cmd [consume_arg]
		switch -exact -- $try_cmd {
			"catch" {
				if {[llength $args] == 0} {
					raise ArgumentError "Wrong number of args: No args supplied\
						to try's catch command."
				}
				# Set default match type
				set catch_match_type "glob"
				# Check for flags that explicitly set the match type
				switch -glob -- [next_arg] {
					"-ex" {
						consume_arg
						set catch_match_type "exact"
					}
					"-re" {
						consume_arg
						set catch_match_type "regex"
					}
					"-gl" {
						consume_arg
						set catch_match_type "glob"
					}
					"--" {}
					"-*" {
						# Reserve all flags beginning with - for future use
						raise ArgumentError "Bad option [next_arg] for\
							try...catch."
					}
				}
				if {[next_arg] == "--"} {
					consume_arg
				}
				if {[llength $args] == 0} {
					raise ArgumentError "Wrong number of args: No error type\
						supplied for catch."
				} elseif {[llength $args] == 1} {
					raise ArgumentError "Wrong number of args: No script\
						supplied for catch."
				}
				set catch_exception_type [consume_arg]
				if {[string first "\n" $catch_exception_type] >= 0} {
					raise ArgumentError "Bad args: no (or badly formed) error\
						type for catch."
				}
				set catch_match [create_match_code $catch_match_type \
					$catch_exception_type]
				set catch_block [consume_arg]
				lappend catch_list $catch_match
				lappend catch_list $catch_block
			}
			"finally" {
				if {[llength $args] == 0} {
					raise ArgumentError "Wrong number of args: No args supplied\
						to try's finally command."
				} elseif {[llength $args] >= 2} {
					raise ArgumentError "Wrong number of args: Nothing can\
						follow the finally code block."
				}
				set finally_block [consume_arg]
			}
			"default" {
				raise ArgumentError "Bad args: should be try code_block\
					?catch type code_block?* ?finally code_block?"
			}
		}
	}

	# Return values/codes are overridden with this priority (highest is top
	# priority):
	#     finally
	#     catch
	#     try

	# Perform the try
	set status_try [catch {uplevel 1 $try_block} try_result]
	if {$status_try == 1} {
		set errorCode_try $::errorCode
		set errorInfo_try [clean_errorInfo $::errorInfo try]
	}

	# Perform the catch if an error has occurred
	set status_catch 0
	if {$status_try == 1} {
		# Find and execute the correct catch block before moving to the finally
		# block.
		if {[catch {set error_type [get_error_type $try_result]}]} {
			# Since this isn't our error pair, it gets assigned the special
			# type for built-in errors
			set error_type TclBuiltInError
		}
		set status_catch [catch {
			uplevel 1 [get_code_for_error $catch_list $error_type]
		} catch_result]
		if {$status_catch == 1} {
			set errorCode_catch $::errorCode
			set errorInfo_catch [clean_errorInfo $::errorInfo catch]
		} elseif {$status_catch != 5} {
			# A status code of 5 indicates that the exception is unhandled by
			# this try block, and no catch has been invoked. Since the status
			# is not 5 here, catch IS invoked, so set the status of the try
			# block to that of the catch block.
			set status_try $status_catch
			set try_result $catch_result
		}
	}

	# Perform the finally last if it has been defined
	if {[string equal "" $finally_block]} {
		set status_finally -1
	} else {
		set status_finally [catch {uplevel 1 $finally_block} finally_result]
	}

	if {$status_finally == 1} {
		set errorCode_finally $::errorCode
		set errorInfo_finally [clean_errorInfo $::errorInfo finally]
	}

	if {$status_finally > 0} {
		# Return codes in the finally block override everything else.
		if {$status_finally != 1} {
			return -code $status_finally $finally_result
		}
		# Build a new error pair if necessary
		if {[catch {set error_type [get_error_type $finally_result]}]} {
			set error_type TclBuiltInError
			set error_message $finally_result
		} else {
			set error_message [get_error_message $finally_result]
		}
		return -code $status_finally -errorcode $errorCode_finally \
		  -errorinfo "try...finally block failed with\
		  error:\n$errorInfo_finally" \
		  [build_error_pair ${error_type} ${error_message}]
	} elseif {$status_catch > 0 && $status_catch < 5} {
		# Return codes in the catch block override other returns, but a
		# status of 5 is our custom return code for unhandled errors
		if {$status_catch != 1} {
			return -code $status_catch $catch_result
		}
		# Build a new error pair if necessary
		if {[catch {set error_type [get_error_type $catch_result]}]} {
			set error_type TclBuiltInError
			set error_message $catch_result
		} else {
			set error_message [get_error_message $catch_result]
		}
		return -code 1 -errorcode $errorCode_catch \
		  -errorinfo "try...catch block failed with error:\n$errorInfo_catch" \
		  [build_error_pair ${error_type} ${error_message}]
	} elseif {$status_finally == -1 || $status_try != 0} {
		# Return with the status of the try block
		if {$status_try != 1} {
			return -code $status_try $try_result
		}
		return -code 1 -errorcode $errorCode_try \
		  -errorinfo $errorInfo_try $try_result
	} else {
		return -code 0 $finally_result
	}
}

# Raise an error with a specified type.
proc raise {errorType errorMsg} {
	if {[string equal $errorType TclBuiltInError]} {
		# Don't raise errors of type "TclBuiltInError" yourself, please.
		set errorType "Faux$errorType"
	}
	# Clean up the errorType in case the user got fancy with the formatting
	# (Remove newlines, leading/trailing whitespace, consecutive whitespace)
	set errorType [regsub -all {\s+} \
		[string trim [join [split $errorType]]] " "]

	return -code error [build_error_pair $errorType $errorMsg]
}

# Create and return the error pair
proc build_error_pair {errorType errorMsg} {
	return [list $errorType $errorMsg]
}

# Return 1 if the error is our special "error pair" type, else 0
proc is_error_pair {errorVal} {
	if {[llength $errorVal] == 2} {
		return 1
	}
	return 0
}

proc get_error_type {errorPair} {
	if {[is_error_pair $errorPair]} {
		return [lindex $errorPair 0]
	} else {
		error "Failed to get error type. The following error is not a valid\
			error pair: $errorPair"
	}
}

proc get_error_message {errorPair} {
	if {[is_error_pair $errorPair]} {
		return [lindex $errorPair 1]
	} else {
		raise ValueError "Failed to get error message. The following error is\
			not a valid error pair: $errorPair"
	}
}

# Return TCL code that executes a test with the given match type
proc create_match_code {match_type type_match_string} {
	switch -exact -- $match_type {
		"glob" {
			return "\[string match {$type_match_string} \$error_type\]"
		}
		"exact" {
			return "\[string equal {$type_match_string} \$error_type\]"
		}
		"regex" {
			return "\[regexp {^$type_match_string\$} \$error_type\]"
		}
	}
	raise ValueError "Invalid match type."
}

################################################################################
# Execute the match test code in the catch_list and return the matching code to
# execute. Returns a special code number "5" to indicate that there is no code
# to handle this exception.
################################################################################
proc get_code_for_error {catch_list error_type} {
	foreach {match_expression catch_code} $catch_list {
		if {[expr $match_expression]} {
			return $catch_code
		}
	}
	return -code 5 "Unhandled Error"
}

################################################################################
# Manipulates the given errorInfo value to translate the call to "uplevel" to a
# direct reference to the try block
################################################################################
proc clean_errorInfo {errorInfo_text {block_name try}} {
	set regex_string {(\n\s+\(")uplevel(" body.*)}
	append regex_string {(\n\s+invoked from within\n}
	switch -exact -- $block_name {
		try {
			append regex_string {"uplevel 1 \$try_block")$}
		}
		catch {
			append regex_string {"uplevel 1 \[get_code_for_error.*")$}
		}
		finally {
			append regex_string {"uplevel 1 \$finally_block")$}
		}
		default {
			raise ValueError "Invalid block name ($block_name)"
		}
	}
	return [regsub -line $regex_string $errorInfo_text "\\1$block_name\\2"]
}

################################################################################
# Peeks at the next argument in the local "args" list. Returns an error if no
# args are found, otherwise returns the argument.
################################################################################
proc next_arg {} {
	upvar args args
	if {[llength $args] == 0} {
		raise OutOfRangeError "No args left to peek at."
	}

	return [lindex $args 0]
}

################################################################################
# Convenience function to access the local args array, get the first value,
# then remove it from the front of the list in preparation to consume the next
# arg.
################################################################################
proc consume_arg {} {
	upvar args args

	return [pop -front args]
}

################################################################################
# Basic pop function to remove an element in the named list and return its
# value. If the "-front" argument is specified, first element in the list is
# popped, otherwise, the last element is popped.
#
# Usage: "pop ?-front? list_name"
################################################################################
proc pop {args} {
	# Arg parsing section
	if {[llength $args] == 0 || [llength $args] > 2} {
		raise ArgumentError "wrong # args: should be \"pop ?-front? list_name\""
	}
	set list_name [lindex $args end]
	set args [lrange $args 0 end-1]
	if {[llength $args] == 1 && [string equal [lindex $args 0] -front]} {
		set use_front 1
	} else {
		set use_front 0
	}

	# Manipulate the named list
	upvar $list_name list_operand

	if {[llength $list_operand] == 0} {
		raise ValueError "Cannot pop from empty list."
	}
	if {!$use_front} {
		set ret [lindex $list_operand end]
		set list_operand [lrange $list_operand 0 end-1]
	} else {
		set ret [lindex $list_operand 0]
		set list_operand [lrange $list_operand 1 end]
	}

	return $ret
}

} ;# End namespace exceptions
namespace import exceptions::*
