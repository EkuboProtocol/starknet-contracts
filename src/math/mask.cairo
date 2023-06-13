// Returns (2**n) - 1
fn mask(n: u8) -> u128 {
    assert(n < 128, 'mask');
    if (n > 63) {
        if (n > 95) {
            if (n > 111) {
                if (n > 119) {
                    if (n > 123) {
                        if (n > 125) {
                            if (n == 126) {
                                0x7fffffffffffffffffffffffffffffff
                            } else {
                                0xffffffffffffffffffffffffffffffff
                            }
                        } else {
                            if (n == 124) {
                                0x1fffffffffffffffffffffffffffffff
                            } else {
                                0x3fffffffffffffffffffffffffffffff
                            }
                        }
                    } else {
                        if (n > 121) {
                            if (n == 122) {
                                0x7ffffffffffffffffffffffffffffff
                            } else {
                                0xfffffffffffffffffffffffffffffff
                            }
                        } else {
                            if (n == 120) {
                                0x1ffffffffffffffffffffffffffffff
                            } else {
                                0x3ffffffffffffffffffffffffffffff
                            }
                        }
                    }
                } else {
                    if (n > 115) {
                        if (n > 117) {
                            if (n == 118) {
                                0x7fffffffffffffffffffffffffffff
                            } else {
                                0xffffffffffffffffffffffffffffff
                            }
                        } else {
                            if (n == 116) {
                                0x1fffffffffffffffffffffffffffff
                            } else {
                                0x3fffffffffffffffffffffffffffff
                            }
                        }
                    } else {
                        if (n > 113) {
                            if (n == 114) {
                                0x7ffffffffffffffffffffffffffff
                            } else {
                                0xfffffffffffffffffffffffffffff
                            }
                        } else {
                            if (n == 112) {
                                0x1ffffffffffffffffffffffffffff
                            } else {
                                0x3ffffffffffffffffffffffffffff
                            }
                        }
                    }
                }
            } else {
                if (n > 103) {
                    if (n > 107) {
                        if (n > 109) {
                            if (n == 110) {
                                0x7fffffffffffffffffffffffffff
                            } else {
                                0xffffffffffffffffffffffffffff
                            }
                        } else {
                            if (n == 108) {
                                0x1fffffffffffffffffffffffffff
                            } else {
                                0x3fffffffffffffffffffffffffff
                            }
                        }
                    } else {
                        if (n > 105) {
                            if (n == 106) {
                                0x7ffffffffffffffffffffffffff
                            } else {
                                0xfffffffffffffffffffffffffff
                            }
                        } else {
                            if (n == 104) {
                                0x1ffffffffffffffffffffffffff
                            } else {
                                0x3ffffffffffffffffffffffffff
                            }
                        }
                    }
                } else {
                    if (n > 99) {
                        if (n > 101) {
                            if (n == 102) {
                                0x7fffffffffffffffffffffffff
                            } else {
                                0xffffffffffffffffffffffffff
                            }
                        } else {
                            if (n == 100) {
                                0x1fffffffffffffffffffffffff
                            } else {
                                0x3fffffffffffffffffffffffff
                            }
                        }
                    } else {
                        if (n > 97) {
                            if (n == 98) {
                                0x7ffffffffffffffffffffffff
                            } else {
                                0xfffffffffffffffffffffffff
                            }
                        } else {
                            if (n == 96) {
                                0x1ffffffffffffffffffffffff
                            } else {
                                0x3ffffffffffffffffffffffff
                            }
                        }
                    }
                }
            }
        } else {
            if (n > 79) {
                if (n > 87) {
                    if (n > 91) {
                        if (n > 93) {
                            if (n == 94) {
                                0x7fffffffffffffffffffffff
                            } else {
                                0xffffffffffffffffffffffff
                            }
                        } else {
                            if (n == 92) {
                                0x1fffffffffffffffffffffff
                            } else {
                                0x3fffffffffffffffffffffff
                            }
                        }
                    } else {
                        if (n > 89) {
                            if (n == 90) {
                                0x7ffffffffffffffffffffff
                            } else {
                                0xfffffffffffffffffffffff
                            }
                        } else {
                            if (n == 88) {
                                0x1ffffffffffffffffffffff
                            } else {
                                0x3ffffffffffffffffffffff
                            }
                        }
                    }
                } else {
                    if (n > 83) {
                        if (n > 85) {
                            if (n == 86) {
                                0x7fffffffffffffffffffff
                            } else {
                                0xffffffffffffffffffffff
                            }
                        } else {
                            if (n == 84) {
                                0x1fffffffffffffffffffff
                            } else {
                                0x3fffffffffffffffffffff
                            }
                        }
                    } else {
                        if (n > 81) {
                            if (n == 82) {
                                0x7ffffffffffffffffffff
                            } else {
                                0xfffffffffffffffffffff
                            }
                        } else {
                            if (n == 80) {
                                0x1ffffffffffffffffffff
                            } else {
                                0x3ffffffffffffffffffff
                            }
                        }
                    }
                }
            } else {
                if (n > 71) {
                    if (n > 75) {
                        if (n > 77) {
                            if (n == 78) {
                                0x7fffffffffffffffffff
                            } else {
                                0xffffffffffffffffffff
                            }
                        } else {
                            if (n == 76) {
                                0x1fffffffffffffffffff
                            } else {
                                0x3fffffffffffffffffff
                            }
                        }
                    } else {
                        if (n > 73) {
                            if (n == 74) {
                                0x7ffffffffffffffffff
                            } else {
                                0xfffffffffffffffffff
                            }
                        } else {
                            if (n == 72) {
                                0x1ffffffffffffffffff
                            } else {
                                0x3ffffffffffffffffff
                            }
                        }
                    }
                } else {
                    if (n > 67) {
                        if (n > 69) {
                            if (n == 70) {
                                0x7fffffffffffffffff
                            } else {
                                0xffffffffffffffffff
                            }
                        } else {
                            if (n == 68) {
                                0x1fffffffffffffffff
                            } else {
                                0x3fffffffffffffffff
                            }
                        }
                    } else {
                        if (n > 65) {
                            if (n == 66) {
                                0x7ffffffffffffffff
                            } else {
                                0xfffffffffffffffff
                            }
                        } else {
                            if (n == 64) {
                                0x1ffffffffffffffff
                            } else {
                                0x3ffffffffffffffff
                            }
                        }
                    }
                }
            }
        }
    } else {
        if (n > 31) {
            if (n > 47) {
                if (n > 55) {
                    if (n > 59) {
                        if (n > 61) {
                            if (n == 62) {
                                0x7fffffffffffffff
                            } else {
                                0xffffffffffffffff
                            }
                        } else {
                            if (n == 60) {
                                0x1fffffffffffffff
                            } else {
                                0x3fffffffffffffff
                            }
                        }
                    } else {
                        if (n > 57) {
                            if (n == 58) {
                                0x7ffffffffffffff
                            } else {
                                0xfffffffffffffff
                            }
                        } else {
                            if (n == 56) {
                                0x1ffffffffffffff
                            } else {
                                0x3ffffffffffffff
                            }
                        }
                    }
                } else {
                    if (n > 51) {
                        if (n > 53) {
                            if (n == 54) {
                                0x7fffffffffffff
                            } else {
                                0xffffffffffffff
                            }
                        } else {
                            if (n == 52) {
                                0x1fffffffffffff
                            } else {
                                0x3fffffffffffff
                            }
                        }
                    } else {
                        if (n > 49) {
                            if (n == 50) {
                                0x7ffffffffffff
                            } else {
                                0xfffffffffffff
                            }
                        } else {
                            if (n == 48) {
                                0x1ffffffffffff
                            } else {
                                0x3ffffffffffff
                            }
                        }
                    }
                }
            } else {
                if (n > 39) {
                    if (n > 43) {
                        if (n > 45) {
                            if (n == 46) {
                                0x7fffffffffff
                            } else {
                                0xffffffffffff
                            }
                        } else {
                            if (n == 44) {
                                0x1fffffffffff
                            } else {
                                0x3fffffffffff
                            }
                        }
                    } else {
                        if (n > 41) {
                            if (n == 42) {
                                0x7ffffffffff
                            } else {
                                0xfffffffffff
                            }
                        } else {
                            if (n == 40) {
                                0x1ffffffffff
                            } else {
                                0x3ffffffffff
                            }
                        }
                    }
                } else {
                    if (n > 35) {
                        if (n > 37) {
                            if (n == 38) {
                                0x7fffffffff
                            } else {
                                0xffffffffff
                            }
                        } else {
                            if (n == 36) {
                                0x1fffffffff
                            } else {
                                0x3fffffffff
                            }
                        }
                    } else {
                        if (n > 33) {
                            if (n == 34) {
                                0x7ffffffff
                            } else {
                                0xfffffffff
                            }
                        } else {
                            if (n == 32) {
                                0x1ffffffff
                            } else {
                                0x3ffffffff
                            }
                        }
                    }
                }
            }
        } else {
            if (n > 15) {
                if (n > 23) {
                    if (n > 27) {
                        if (n > 29) {
                            if (n == 30) {
                                0x7fffffff
                            } else {
                                0xffffffff
                            }
                        } else {
                            if (n == 28) {
                                0x1fffffff
                            } else {
                                0x3fffffff
                            }
                        }
                    } else {
                        if (n > 25) {
                            if (n == 26) {
                                0x7ffffff
                            } else {
                                0xfffffff
                            }
                        } else {
                            if (n == 24) {
                                0x1ffffff
                            } else {
                                0x3ffffff
                            }
                        }
                    }
                } else {
                    if (n > 19) {
                        if (n > 21) {
                            if (n == 22) {
                                0x7fffff
                            } else {
                                0xffffff
                            }
                        } else {
                            if (n == 20) {
                                0x1fffff
                            } else {
                                0x3fffff
                            }
                        }
                    } else {
                        if (n > 17) {
                            if (n == 18) {
                                0x7ffff
                            } else {
                                0xfffff
                            }
                        } else {
                            if (n == 16) {
                                0x1ffff
                            } else {
                                0x3ffff
                            }
                        }
                    }
                }
            } else {
                if (n > 7) {
                    if (n > 11) {
                        if (n > 13) {
                            if (n == 14) {
                                0x7fff
                            } else {
                                0xffff
                            }
                        } else {
                            if (n == 12) {
                                0x1fff
                            } else {
                                0x3fff
                            }
                        }
                    } else {
                        if (n > 9) {
                            if (n == 10) {
                                0x7ff
                            } else {
                                0xfff
                            }
                        } else {
                            if (n == 8) {
                                0x1ff
                            } else {
                                0x3ff
                            }
                        }
                    }
                } else {
                    if (n > 3) {
                        if (n > 5) {
                            if (n == 6) {
                                0x7f
                            } else {
                                0xff
                            }
                        } else {
                            if (n == 4) {
                                0x1f
                            } else {
                                0x3f
                            }
                        }
                    } else {
                        if (n > 1) {
                            if (n == 2) {
                                0x7
                            } else {
                                0xf
                            }
                        } else {
                            if (n == 0) {
                                0x1
                            } else {
                                0x3
                            }
                        }
                    }
                }
            }
        }
    }
}
